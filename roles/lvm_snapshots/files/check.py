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
import json
import subprocess
import sys

_VGS_COMMAND = '/usr/sbin/vgs'
_LVS_COMMAND = '/usr/sbin/lvs'

class CheckException(Exception):
    """ Exception wrapper """


def _main():
    if len(sys.argv) < 2 or not sys.argv[1]:
        print("List of volumes was not provided")
        sys.exit(1)

    try:
        volumes = json.loads(sys.argv[1])
    except json.decoder.JSONDecodeError:
        print("Provided volume list '{volumes}' it not a valid json string".format(volumes=sys.argv[1]))
        sys.exit(1)

    groups_names = set(vol['vg'] for vol in volumes)
    groups_info = {
        group: _get_group_info(group) for group in groups_names
    }

    for vol in volumes:
        groups_info[vol["vg"]]['requested_size'] += _calc_requested_size(groups_info[vol["vg"]], vol)

    enough_space = all(group['requested_size'] > group['free'] for _, group in groups_info.items())

    if not enough_space:
        sys.exit(0)
    print(json.dumps(groups_info))
    sys.exit(1)


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


if __name__ == '__main__':
    _main()
