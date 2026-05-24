import 'package:flutter/material.dart';

class ConvertProgress extends StatelessWidget {
  final double progress;
  final String status;

  const ConvertProgress({
    super.key,
    required this.progress,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 2.5,
                  color: Colors.blue,
                  backgroundColor: Colors.blue.shade100,
                ),
              ),
              const SizedBox(width: 12),
              Text(status, style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.w500)),
              const Spacer(),
              Text('${(progress * 100).toInt()}%',
                style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              color: Colors.blue,
              backgroundColor: Colors.blue.shade100,
            ),
          ),
        ],
      ),
    );
  }
}
