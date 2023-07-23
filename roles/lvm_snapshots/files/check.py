'''
Check is there is enough space to created all the requested snapshots
The input should be a json string array.
Each element should have the following keys:
- vg: Name of the volume group
- lv: Name of the Logical Volume
- size: The size of the requested snapshot.
        Follow (https://docs.ansible.com/ansible/latest/collections/community/general/lvol_module.html#parameter-size)
        without support for sign
'''
import argparse
import json
import math
import os
import subprocess
import sys

_VGS_COMMAND = '/usr/sbin/vgs'
_LVS_COMMAND = '/usr/sbin/lvs'

_EXIT_CODE_SUCCESS = 0
_EXIT_CODE_VOLUME_GROUP_SPACE = 1
_EXIT_CODE_FILE_SYSTEM_TYPE = 2
_EXIT_CODE_VOLUME_SPACE = 3

_supported_filesystems = [
    '',
    'ext2',
    'ext3',
    'ext4'
]

class CheckException(Exception):
    """ Exception wrapper """

parser = argparse.ArgumentParser()
parser.add_argument('that', help='What should the script check', type=str, choices=['snapshots', 'resize'])
parser.add_argument('volumes', help='Volumes JSON array in a string', type=str)

def _main():
    args = parser.parse_args()

    try:
        volumes = json.loads(args.volumes)
    except json.decoder.JSONDecodeError:
        print("Provided volume list '{volumes}' it not a valid json string".format(volumes=sys.argv[1]))
        sys.exit(1)

    groups_names = set(vol['vg'] for vol in volumes)
    groups_info = {
        group: _get_group_info(group) for group in groups_names
    }

    for vol in volumes:
        vol['normalized_size'] = _calc_requested_size(groups_info[vol["vg"]], vol)
        groups_info[vol["vg"]]['requested_size'] += vol['normalized_size']

    if args.that == 'snapshots':
        exit_code = _check_free_size_for_snapshots(groups_info)
    if args.that == 'resize':
        exit_code = _check_free_size_for_resize(volumes, groups_info)

    sys.exit(exit_code)


def _check_free_size_for_snapshots(groups_info):
    return _check_requested_size(groups_info, 'free')


def _check_free_size_for_resize(volumes, groups_info):
    exit_code = _check_requested_size(groups_info, 'size')
    if exit_code != _EXIT_CODE_SUCCESS:
        return exit_code

    mtab = _parse_mtab()

    for volume in volumes:
        mtab_entry = mtab.get("/dev/mapper/{vg}-{lv}".format(vg=volume['vg'], lv=volume['lv']))
        volume['fs_type'] = mtab_entry['type'] if mtab_entry else ''
        volume['fs_size'] = _calc_filesystem_size(mtab_entry) if mtab_entry else 0

    filesystems_supported = all(volume['fs_type'] in _supported_filesystems for volume in volumes)
    if not filesystems_supported:
        exit_code = _EXIT_CODE_FILE_SYSTEM_TYPE

    enough_space = all(vol['normalized_size'] > vol['fs_size'] for vol in volumes)
    if not enough_space:
        exit_code = _EXIT_CODE_VOLUME_SPACE

    if exit_code != _EXIT_CODE_SUCCESS:
        print(json.dumps(_to_printable_volumes(volumes)))

    return exit_code


def _check_requested_size(groups_info, group_field):
    enough_space = all(group['requested_size'] <= group[group_field] for _, group in groups_info.items())
    if not enough_space:
        print(json.dumps(groups_info))
        return _EXIT_CODE_VOLUME_GROUP_SPACE
    return _EXIT_CODE_SUCCESS


def _get_group_info(group):
    group_info_str = subprocess.check_output([_VGS_COMMAND, group, '-v', '--reportformat', 'json'])
    group_info_json = json.loads(group_info_str)
    group_info = group_info_json['report'][0]['vg'][0]
    return {
        'name': group,
        'size': _get_size_from_report(group_info['vg_size']),
        'free': _get_size_from_report(group_info['vg_free']),
        'requested_size': 0
    }


def _calc_requested_size(group_info, volume):
    unit = 'm'
    requested_size = volume.get('size', 0)
    if requested_size == 0:
        # handle thin provisioning
        pass
    if isinstance(requested_size, int):
        size = requested_size
    else:
        parts = requested_size.split('%')
        if len(parts) == 2:
            percent = parts[0]
            percent_of = parts[1]
            if percent_of == 'VG':
                size = group_info['size'] * percent / 100
            elif percent_of == 'FREE':
                size = group_info['free'] * percent / 100
            elif percent_of == 'ORIGIN':
                origin_size = _get_volume_size(volume)
                size = origin_size * percent / 100
            else:
                raise CheckException("Unsupported base type {base_type}".format(base_type=percent_of))
        else:
            try:
                size = int(requested_size[:-1])
                unit = requested_size[-1].lower()
            except ValueError as exc:
                raise CheckException('Failed to read requested size {size}'.format(size=requested_size)) from exc
    return _convert_to_bytes(size, unit)


def _get_volume_size(vol):
    volume_info_str = subprocess.check_output(
        [_LVS_COMMAND, "{vg}/{lv}".format(vg=vol['vg'],lv=vol['lv']), '-v', '--reportformat', 'json']
    )
    volume_info_json = json.loads(volume_info_str)
    volume_info = volume_info_json['report'][0]['lv'][0]
    return _get_size_from_report(volume_info['lv_size'])


def _get_size_from_report(reported_size):
    try:
        size = float(reported_size)
        unit = 'm'
    except ValueError:
        if reported_size[0] == '<':
            reported_size = reported_size[1:]
        size = float(reported_size[:-1])
        unit = reported_size[-1].lower()
    return _convert_to_bytes(size, unit)


def _calc_filesystem_size(mtab_entry):
    fs_stat = os.statvfs(mtab_entry['mount_point'])
    return (fs_stat.f_blocks - fs_stat.f_bfree) * fs_stat.f_bsize


def _parse_mtab():
    mtab = {}
    with open('/etc/mtab') as f:
        for m in f:
            fs_spec, fs_file, fs_vfstype, _fs_mntops, _fs_freq, _fs_passno = m.split()
            mtab[fs_spec] = {
                'mount_point': fs_file,
                'type': fs_vfstype
            }
    return mtab


def _convert_to_bytes(size, unit):
    convertion_table = {
        'b': 1024 ** 0,
        'k': 1024 ** 1,
        'm': 1024 ** 2,
        'g': 1024 ** 3,
        't': 1024 ** 4,
        'p': 1024 ** 5,
        'e': 1024 ** 6,
    }
    return size * convertion_table[unit]


def _convert_to_unit_size(bytes):
    units = ['b', 'k', 'm', 'g', 't', 'p', 'e']
    i = 0
    while bytes >= 1024:
        i += 1
        bytes /= 1024
    # Round down bytes to two digits
    bytes = math.floor(bytes * 100) / 100
    return "{size}{unit}".format(size=bytes, unit=units[i])


def _to_printable_volumes(volumes):
    return {
        volume['vg'] + "_" + volume['lv']: {
            'file_system_type': volume['fs_type'],
            'used': _convert_to_unit_size(volume['fs_size']),
            'requested_size': _convert_to_unit_size(volume['normalized_size'])
        } for volume in volumes
    }

if __name__ == '__main__':
    _main()
