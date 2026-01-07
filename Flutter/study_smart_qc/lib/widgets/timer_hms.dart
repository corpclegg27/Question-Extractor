import 'package:flutter/material.dart';

class Timer_HMS extends StatelessWidget {
  final Duration duration;
  final TextStyle? style;
  final TextAlign? textAlign;

  const Timer_HMS({
    super.key,
    required this.duration,
    this.style,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");

    final int hours = duration.inHours;
    final int minutes = duration.inMinutes.remainder(60);
    final int seconds = duration.inSeconds.remainder(60);

    String formattedTime;

    if (hours > 0) {
      // Format: HH:MM:SS
      formattedTime = "${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}";
    } else {
      // Format: MM:SS (Hours are hidden)
      formattedTime = "${twoDigits(minutes)}:${twoDigits(seconds)}";
    }

    return Text(
      formattedTime,
      style: style,
      textAlign: textAlign,
    );
  }
}