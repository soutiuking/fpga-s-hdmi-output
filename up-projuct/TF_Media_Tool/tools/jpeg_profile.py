"""The baseline 4:2:0 profile consumed by the fixed-Huffman FPGA decoder."""

# ISO/IEC 10918-1 Annex K default tables: selector, 16 counts, symbols.
STANDARD_DHT = {key: bytes.fromhex(value) for key, value in {
    0x00: '0000010501010101010100000000000000000102030405060708090a0b',
    0x01: '0100030101010101010101010000000000000102030405060708090a0b',
    0x10: ('100002010303020403050504040000017d01020300041105122131410613516107227114328191a1082342b1c11552d1f02433627282090a161718191a25262728292a3435363738393a434445464748494a535455565758595a636465666768696a737475767778797a838485868788898a92939495969798999aa2a3a4a5a6a7a8a9aab2b3b4b5b6b7b8b9bac2c3c4c5c6c7c8c9cad2d3d4d5d6d7d8d9dae1e2e3e4e5e6e7e8e9eaf1f2f3f4f5f6f7f8f9fa'),
    0x11: ('1100020102040403040705040400010277000102031104052131061241510761711322328108144291a1b1c109233352f0156272d10a162434e125f11718191a262728292a35363738393a434445464748494a535455565758595a636465666768696a737475767778797a82838485868788898a92939495969798999aa2a3a4a5a6a7a8a9aab2b3b4b5b6b7b8b9bac2c3c4c5c6c7c8c9cad2d3d4d5d6d7d8d9dae2e3e4e5e6e7e8e9eaf2f3f4f5f6f7f8f9fa'),
}.items()}


def check_hardware_profile(data):
    """Reject optimized tables, alternate scan mappings and restart streams."""
    if data[:2] != b'\xff\xd8':
        raise ValueError('JPEG SOI missing')
    pos, seen, sof = 2, set(), False
    while pos < len(data):
        if data[pos:pos+1] != b'\xff':
            raise ValueError('Invalid JPEG header marker')
        while pos < len(data) and data[pos] == 255:
            pos += 1
        if pos + 3 > len(data):
            raise ValueError('Truncated JPEG marker')
        marker = data[pos]
        length = int.from_bytes(data[pos+1:pos+3], 'big')
        if length < 2 or pos + 1 + length > len(data):
            raise ValueError('Invalid JPEG segment length')
        payload = data[pos+3:pos+1+length]
        pos += 1 + length
        if marker == 0xc4:
            offset = 0
            while offset < len(payload):
                table = payload[offset]
                if offset + 17 > len(payload):
                    raise ValueError('Truncated JPEG DHT counts')
                end = offset + 17 + sum(payload[offset+1:offset+17])
                if table not in STANDARD_DHT or payload[offset:end] != STANDARD_DHT[table]:
                    raise ValueError('FPGA requires standard JPEG Huffman tables; encode with optimize=False')
                seen.add(table)
                offset = end
        elif marker == 0xc0:
            if sof or payload != bytes.fromhex('0801e0028003012200021101031101'):
                raise ValueError('FPGA requires 640x480 baseline YCbCr 4:2:0 with standard component mapping')
            sof = True
        elif marker == 0xda:
            if not sof or seen != set(STANDARD_DHT):
                raise ValueError('JPEG must define SOF0 and all four standard Huffman tables before SOS')
            if payload != bytes.fromhex('03010002110311003f00'):
                raise ValueError('Unsupported JPEG scan/table selectors')
            # The entropy payload may contain FF00 escapes, but no restarts or
            # additional scans. Validate without mistaking an escape for EOI.
            while pos < len(data):
                if data[pos] != 255:
                    pos += 1
                    continue
                following = data[pos+1:pos+2]
                if following == b'\x00':
                    pos += 2
                elif following == b'\xd9' and pos + 2 == len(data):
                    return
                else:
                    raise ValueError('JPEG restart markers or multiple scans are unsupported')
            raise ValueError('JPEG EOI missing')
        elif marker == 0xdd:
            raise ValueError('JPEG restart intervals are unsupported')
        elif marker != 0xdb and not (0xe0 <= marker <= 0xef or marker == 0xfe):
            raise ValueError(f'Unsupported JPEG marker FF{marker:02X}')
    raise ValueError('JPEG SOS missing')
