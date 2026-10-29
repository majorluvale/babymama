String _two(int n) => n.toString().padLeft(2, '0');

/// 12500 -> "KSh 12,500"
String formatKes(num amount) {
  final digits = amount.round().abs().toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return '${amount < 0 ? '-' : ''}KSh $out';
}

String formatDate(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';

String formatDateTime(DateTime d) => '${formatDate(d)} ${_two(d.hour)}:${_two(d.minute)}';

String formatTime(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';
