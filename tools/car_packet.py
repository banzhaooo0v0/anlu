"""C50X binary packet helper. This tool never opens a port or moves a vehicle."""
import argparse
import json
import struct
from functools import reduce
from operator import xor


def command(vx=0, vy=0, wz=0):
    """Signed mm/s, mm/s, mrad/s; three big-endian int16 words."""
    payload = b'\x7b\x00\x00' + struct.pack('>hhh', vx, vy, wz)
    return payload + bytes([reduce(xor, payload, 0), 0x7D])


def telemetry(frame):
    if len(frame) != 24 or frame[0] != 0x7B or frame[-1] != 0x7D:
        raise ValueError('Expected 24 bytes with 7B header and 7D trailer')
    if reduce(xor, frame[:22], 0) != frame[22]:
        raise ValueError('BCC mismatch')
    fields = struct.unpack('>9hH', frame[2:22])
    names = ['vx_mm_s', 'vy_mm_s', 'wz_mrad_s', 'accel_x_raw', 'accel_y_raw',
             'accel_z_raw', 'gyro_x_raw', 'gyro_y_raw', 'gyro_z_raw', 'battery_mv']
    return dict(flag_stop=frame[1], **dict(zip(names, fields)))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest='action', required=True)
    enc = sub.add_parser('encode')
    enc.add_argument('--vx', type=int, default=0)
    enc.add_argument('--vy', type=int, default=0)
    enc.add_argument('--wz', type=int, default=0)
    dec = sub.add_parser('decode')
    dec.add_argument('hex_bytes', help='One 24-byte feedback frame, in hex')
    sub.add_parser('selftest')
    a = p.parse_args()
    if a.action == 'encode':
        print(command(a.vx, a.vy, a.wz).hex(' ').upper())
    elif a.action == 'decode':
        print(json.dumps(telemetry(bytes.fromhex(a.hex_bytes)), indent=2))
    else:
        assert command() == bytes.fromhex('7B 00 00 00 00 00 00 00 00 7B 7D')
        assert command(100) == bytes.fromhex('7B 00 00 00 64 00 00 00 00 1F 7D')
        assert command(-100) == bytes.fromhex('7B 00 00 FF 9C 00 00 00 00 18 7D')
        payload = b'\x7b\x00' + struct.pack('>9hH', -100, 0, 250, -1, 2, 3, 4, 5, 6, 24000)
        frame = payload + bytes([reduce(xor, payload, 0), 0x7D])
        d = telemetry(frame)
        assert d['vx_mm_s'] == -100 and d['wz_mrad_s'] == 250 and d['battery_mv'] == 24000
        for damaged in [frame[:-1], frame[:-1] + b'\x00', frame[:22] + b'\x00\x7d']:
            try:
                telemetry(damaged)
            except ValueError:
                pass
            else:
                raise AssertionError('Invalid telemetry was accepted')
        print('ALL PACKET HELPER TESTS PASSED')


if __name__ == '__main__':
    main()
