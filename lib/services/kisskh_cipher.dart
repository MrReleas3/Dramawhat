class KissKKeyCipher {
  static int _hashString(String str) {
    int hash = 0;
    for (int i = 0; i < str.length; i++) {
      int int32Hash = (hash & 0xFFFFFFFF).toSigned(32);
      int shifted = (int32Hash << 5).toSigned(32);
      hash = shifted - hash + str.codeUnitAt(i);
    }
    return hash;
  }

  static String _pkcs7Pad(String str) {
    final padLen = 16 - (str.length % 16);
    final padChar = String.fromCharCode(padLen);
    return str + (padChar * padLen);
  }

  static List<dynamic> _stringToWords(String str) {
    final len = str.length;
    final words = List<int>.filled((len + 3) ~/ 4, 0);
    for (int i = 0; i < len; i++) {
      final wordIdx = i >>> 2;
      words[wordIdx] |= (0xFF & str.codeUnitAt(i)) << (24 - (i % 4) * 8);
    }
    return [words, len];
  }

  static String _wordsToHex(List<int> words, int len) {
    final hex = StringBuffer();
    for (int i = 0; i < len; i++) {
      final byteVal = (words[i >>> 2] >>> (24 - (i % 4) * 8)) & 0xFF;
      hex.write(byteVal.toRadixString(16).padLeft(2, '0'));
    }
    return hex.toString();
  }

  static String generateKKey(String epId, bool isSub) {
    const appVer = "2.8.10";
    final guid = isSub ? "VgV52sWhwvBSf8BsM3BRY9weWiiCbtGp" : "62f176f3bb1b5b8e70e39932ad34a0c7";
    const platformVer = "4830201";
    const appName = "kisskh";

    final parts = [
      '',
      epId,
      '',
      'mg3c3b04ba',
      appVer,
      guid,
      platformVer,
      appName,
      appName,
      appName,
      appName,
      appName,
      appName,
      '00',
      ''
    ];

    final checksum = _hashString(parts.join('|'));
    parts.insert(1, checksum.toString());

    final paddedStr = _pkcs7Pad(parts.join('|'));
    final result = _stringToWords(paddedStr);
    final List<int> words = List<int>.from(result[0]);
    final int len = result[1];

    _encryptWords(words);
    return _wordsToHex(words, len).toUpperCase();
  }

  static void _encryptWords(List<int> words) {
    final tables = _getTables();
    final List<int> sbox = tables[0];
    final List<int> t0 = tables[1];
    final List<int> t1 = tables[2];
    final List<int> t2 = tables[3];
    final List<int> t3 = tables[4];
    final List<int> invSbox = tables[5];
    final len = words.length;

    for (int offset = 0; offset < len; offset += 4) {
      List<int> iv;
      if (offset == 0) {
        iv = [0x1504af3, 0x56e619cf, 0x2e42bba6, -0x73c08f07];
      } else {
        iv = words.sublist(offset - 4, offset);
      }

      for (int i = 0; i < 4; i++) {
        words[offset + i] = (words[offset + i] ^ iv[i]).toSigned(32);
      }

      int s0 = (words[offset] ^ sbox[0]).toSigned(32);
      int s1 = (words[offset + 1] ^ sbox[1]).toSigned(32);
      int s2 = (words[offset + 2] ^ sbox[2]).toSigned(32);
      int s3 = (words[offset + 3] ^ sbox[3]).toSigned(32);
      int ptr = 4;

      for (int round = 1; round < 10; round++) {
        final t0Val = (t0[(s0 >>> 24) & 0xFF] ^ t1[(s1 >>> 16) & 0xFF] ^ t2[(s2 >>> 8) & 0xFF] ^ t3[s3 & 0xFF] ^ sbox[ptr++]).toSigned(32);
        final t1Val = (t0[(s1 >>> 24) & 0xFF] ^ t1[(s2 >>> 16) & 0xFF] ^ t2[(s3 >>> 8) & 0xFF] ^ t3[s0 & 0xFF] ^ sbox[ptr++]).toSigned(32);
        final t2Val = (t0[(s2 >>> 24) & 0xFF] ^ t1[(s3 >>> 16) & 0xFF] ^ t2[(s0 >>> 8) & 0xFF] ^ t3[s1 & 0xFF] ^ sbox[ptr++]).toSigned(32);
        s3 = (t0[(s3 >>> 24) & 0xFF] ^ t1[(s0 >>> 16) & 0xFF] ^ t2[(s1 >>> 8) & 0xFF] ^ t3[s2 & 0xFF] ^ sbox[ptr++]).toSigned(32);
        s0 = t0Val;
        s1 = t1Val;
        s2 = t2Val;
      }

      final out0 = ((invSbox[(s0 >>> 24) & 0xFF] << 24 | invSbox[(s1 >>> 16) & 0xFF] << 16 | invSbox[(s2 >>> 8) & 0xFF] << 8 | invSbox[s3 & 0xFF]) ^ sbox[ptr++]).toSigned(32);
      final out1 = ((invSbox[(s1 >>> 24) & 0xFF] << 24 | invSbox[(s2 >>> 16) & 0xFF] << 16 | invSbox[(s3 >>> 8) & 0xFF] << 8 | invSbox[s0 & 0xFF]) ^ sbox[ptr++]).toSigned(32);
      final out2 = ((invSbox[(s2 >>> 24) & 0xFF] << 24 | invSbox[(s3 >>> 16) & 0xFF] << 16 | invSbox[(s0 >>> 8) & 0xFF] << 8 | invSbox[s1 & 0xFF]) ^ sbox[ptr++]).toSigned(32);
      final out3 = ((invSbox[(s3 >>> 24) & 0xFF] << 24 | invSbox[(s0 >>> 16) & 0xFF] << 16 | invSbox[(s1 >>> 8) & 0xFF] << 8 | invSbox[s2 & 0xFF]) ^ sbox[ptr++]).toSigned(32);

      words[offset] = out0;
      words[offset + 1] = out1;
      words[offset + 2] = out2;
      words[offset + 3] = out3;
    }
  }

  static List<List<int>>? _cachedTables;

  static List<List<int>> _getTables() {
    if (_cachedTables != null) return _cachedTables!;
    final sbox = <int>[
      0x4f6bdaa3, -0x61d07350, 0x7f5e722d, -0x61210cec, 0x536620a8, -0x32b653e8, -0x4de821cb, 0x2cc92d21,
      -0x73412227, 0x41f771c1, -0xc1f500c, -0x20d67d2b, 0x2dadde47, 0x6c5aaf86, -0x6045ff8e, 0x409382a7,
      -0x6417db2, -0x6a1bd238, 0xa5e2dba, 0x4acdaf1d, 0x54c72698, -0x3edcf4b0, -0x3482d916, -0x7e4f7609,
      -0x6c9fb16c, 0x524345c4, -0x66c19cd2, 0x188eead9, -0x351884c7, -0x675bc103, 0x19a5dd3, 0x1914b70a,
      -0x4fb1e313, 0x28ea2210, 0x29707fc3, 0x3064c8c9, -0x17593e17, -0x3fb31c07, -0x16c363c6, -0x26a7ab0d,
      -0x4b793324, 0x74ca2f25, -0x62094ce1, 0x44aee7ec
    ];

    final d = List<int>.filled(256, 0);
    for (int i = 0; i < 256; i++) {
      d[i] = i < 128 ? i << 1 : (i << 1) ^ 0x11b;
    }

    int p = 0, q = 0;
    final t0 = List<int>.filled(256, 0);
    final t1 = List<int>.filled(256, 0);
    final t2 = List<int>.filled(256, 0);
    final t3 = List<int>.filled(256, 0);
    final invSbox = List<int>.filled(256, 0);

    for (int i = 0; i < 256; i++) {
      int s = q ^ (q << 1) ^ (q << 2) ^ (q << 3) ^ (q << 4);
      s = (s >>> 8) ^ (s & 0xff) ^ 0x63;
      invSbox[p] = s;
      final x = d[p], y = d[d[x]], z = (0x101 * d[s]) ^ (0x1010100 * s);
      t0[p] = (z << 24) | (z >>> 8);
      t1[p] = (z << 16) | (z >>> 16);
      t2[p] = (z << 8) | (z >>> 24);
      t3[p] = z;
      if (p != 0) {
        p = x ^ d[d[d[y ^ x]]];
        q ^= d[d[q]];
      } else {
        p = q = 1;
      }
    }

    _cachedTables = [sbox, t0, t1, t2, t3, invSbox];
    return _cachedTables!;
  }
}
