import 'dart:convert';

class KissSubDecryptor {
  static Map<String, List<int>> getKeys(String ext) {
    if (ext.contains('.txt1')) {
      return {
        'key': [65, 109, 83, 109, 90, 86, 99, 72, 57, 51, 85, 81, 85, 101, 122, 105],
        'iv': [82, 101, 66, 75, 87, 87, 56, 99, 113, 100, 106, 80, 69, 110, 70, 54]
      };
    }
    if (ext.endsWith('.txt')) {
      return {
        'key': [56, 48, 53, 54, 52, 56, 51, 54, 52, 54, 51, 50, 56, 55, 54, 51],
        'iv': [54, 56, 53, 50, 54, 49, 50, 51, 55, 48, 49, 56, 53, 50, 55, 51]
      };
    }
    return {
      'key': [115, 87, 79, 68, 88, 88, 48, 52, 81, 82, 84, 107, 72, 100, 108, 90],
      'iv': [56, 112, 119, 104, 97, 112, 74, 101, 67, 52, 104, 114, 83, 57, 104, 79]
    };
  }

  static List<int> _base64ToBytes(String b64) {
    String cleanB64 = b64.trim().replaceAll(RegExp(r'=+$'), '');
    // Standardize URL-safe base64 if necessary
    cleanB64 = cleanB64.replaceAll('-', '+').replaceAll('_', '/');
    while (cleanB64.length % 4 != 0) {
      cleanB64 += '=';
    }
    return base64Decode(cleanB64);
  }

  static String _decryptLine(String line, String ext) {
    if (line.isEmpty || line.length < 10) return line;
    final trimmed = line.trim();
    if (trimmed.contains("-->") || RegExp(r'^\d+$').hasMatch(trimmed)) return line;
    if (!RegExp(r'^[A-Za-z0-9+/=_-]+$').hasMatch(trimmed)) return line;

    final keyMap = getKeys(ext);
    final keyBytes = keyMap['key']!;
    final ivBytes = keyMap['iv']!;

    try {
      final ciphertext = _base64ToBytes(trimmed);
      return _decryptAes128Cbc(ciphertext, keyBytes, ivBytes);
    } catch (e) {
      return line;
    }
  }

  static String decryptSubtitleText(String rawContent, String ext) {
    final lines = rawContent.split(RegExp(r'\r?\n'));
    final decryptedLines = lines.map((line) => _decryptLine(line, ext)).toList();
    String content = decryptedLines.join("\n");
    if (!content.startsWith("WEBVTT")) {
      content = "WEBVTT\n\n" + content.replaceAllMapped(
        RegExp(r'(\d{2}:\d{2}:\d{2}),(\d{3})'),
        (match) => "${match.group(1)}.${match.group(2)}",
      );
    }
    return content;
  }

  static String _decryptAes128Cbc(List<int> ciphertext, List<int> keyBytes, List<int> ivBytes) {
    final sbox = <int>[
      0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,
      0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,
      0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
      0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75,
      0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84,
      0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
      0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8,
      0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2,
      0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
      0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb,
      0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
      0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
      0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
      0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e,
      0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
      0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16
    ];

    final invSbox = List<int>.filled(256, 0);
    for (int i = 0; i < 256; i++) invSbox[sbox[i]] = i;

    final w = List<int>.filled(44, 0);
    for (int i = 0; i < 4; i++) {
      w[i] = (keyBytes[4 * i] << 24) | (keyBytes[4 * i + 1] << 16) | (keyBytes[4 * i + 2] << 8) | keyBytes[4 * i + 3];
    }

    final rcon = [0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36];

    int subWord(int wVal) {
      return (sbox[(wVal >>> 24) & 0xff] << 24) |
          (sbox[(wVal >>> 16) & 0xff] << 16) |
          (sbox[(wVal >>> 8) & 0xff] << 8) |
          sbox[wVal & 0xff];
    }

    int rotWord(int wVal) {
      return ((wVal << 8) & 0xFFFFFFFF) | ((wVal >>> 24) & 0xff);
    }

    for (int i = 4; i < 44; i++) {
      int temp = w[i - 1];
      if (i % 4 == 0) {
        temp = subWord(rotWord(temp)) ^ (rcon[i ~/ 4 - 1] << 24);
      }
      w[i] = w[i - 4] ^ temp;
    }

    int mul(int a, int b) {
      int p = 0;
      for (int i = 0; i < 8; i++) {
        if ((b & 1) != 0) p ^= a;
        final hi = a & 0x80;
        a = (a << 1) & 0xff;
        if (hi != 0) a ^= 0x1b;
        b >>>= 1;
      }
      return p;
    }

    void invMixColumns(List<int> s) {
      for (int c = 0; c < 4; c++) {
        final s0 = s[c * 4], s1 = s[c * 4 + 1], s2 = s[c * 4 + 2], s3 = s[c * 4 + 3];
        s[c * 4] = mul(s0, 0x0e) ^ mul(s1, 0x0b) ^ mul(s2, 0x0d) ^ mul(s3, 0x09);
        s[c * 4 + 1] = mul(s0, 0x09) ^ mul(s1, 0x0e) ^ mul(s2, 0x0b) ^ mul(s3, 0x0d);
        s[c * 4 + 2] = mul(s0, 0x0d) ^ mul(s1, 0x09) ^ mul(s2, 0x0e) ^ mul(s3, 0x0b);
        s[c * 4 + 3] = mul(s0, 0x0b) ^ mul(s1, 0x0d) ^ mul(s2, 0x09) ^ mul(s3, 0x0e);
      }
    }

    List<int> decryptBlock(List<int> block, List<int> prevIv) {
      final state = List<int>.from(block);

      for (int c = 0; c < 4; c++) {
        final kw = w[40 + c];
        state[c * 4] ^= (kw >>> 24) & 0xff;
        state[c * 4 + 1] ^= (kw >>> 16) & 0xff;
        state[c * 4 + 2] ^= (kw >>> 8) & 0xff;
        state[c * 4 + 3] ^= kw & 0xff;
      }

      for (int round = 9; round >= 1; round--) {
        final tmp1 = state[13]; state[13] = state[9]; state[9] = state[5]; state[5] = state[1]; state[1] = tmp1;
        final tmp2 = state[2]; state[2] = state[10]; state[10] = tmp2;
        final tmp6 = state[6]; state[6] = state[14]; state[14] = tmp6;
        final tmp3 = state[3]; state[3] = state[7]; state[7] = state[11]; state[11] = state[15]; state[15] = tmp3;

        for (int i = 0; i < 16; i++) state[i] = invSbox[state[i]];

        for (int c = 0; c < 4; c++) {
          final kw = w[round * 4 + c];
          state[c * 4] ^= (kw >>> 24) & 0xff;
          state[c * 4 + 1] ^= (kw >>> 16) & 0xff;
          state[c * 4 + 2] ^= (kw >>> 8) & 0xff;
          state[c * 4 + 3] ^= kw & 0xff;
        }

        invMixColumns(state);
      }

      final tmp1 = state[13]; state[13] = state[9]; state[9] = state[5]; state[5] = state[1]; state[1] = tmp1;
      final tmp2 = state[2]; state[2] = state[10]; state[10] = tmp2;
      final tmp6 = state[6]; state[6] = state[14]; state[14] = tmp6;
      final tmp3 = state[3]; state[3] = state[7]; state[7] = state[11]; state[11] = state[15]; state[15] = tmp3;

      for (int i = 0; i < 16; i++) state[i] = invSbox[state[i]];

      for (int c = 0; c < 4; c++) {
        final kw = w[c];
        state[c * 4] ^= (kw >>> 24) & 0xff;
        state[c * 4 + 1] ^= (kw >>> 16) & 0xff;
        state[c * 4 + 2] ^= (kw >>> 8) & 0xff;
        state[c * 4 + 3] ^= kw & 0xff;
      }

      for (int i = 0; i < 16; i++) state[i] ^= prevIv[i];
      return state;
    }

    final out = <int>[];
    List<int> prev = List<int>.from(ivBytes);

    for (int offset = 0; offset < ciphertext.length; offset += 16) {
      final block = ciphertext.sublist(offset, offset + 16);
      final decrypted = decryptBlock(block, prev);
      out.addAll(decrypted);
      prev = block;
    }

    if (out.isNotEmpty) {
      final padLen = out.last;
      if (padLen > 0 && padLen <= 16 && padLen <= out.length) {
        out.removeRange(out.length - padLen, out.length);
      }
    }
    return utf8.decode(out, allowMalformed: true);
  }
}
