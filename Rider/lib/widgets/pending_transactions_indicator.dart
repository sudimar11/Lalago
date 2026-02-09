import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/offline_transaction_service.dart';

class PendingTransactionsIndicator extends StatelessWidget {
  const PendingTransactionsIndicator({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<OfflineTransactionService>(
      builder: (context, offlineService, child) {
        final pendingCount = offlineService.pendingCount;
        final isProcessing = offlineService.isProcessing;

        if (pendingCount == 0 && !isProcessing) {
          return const SizedBox.shrink();
        }

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isProcessing
                ? Colors.blue.shade50
                : Colors.orange.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isProcessing
                  ? Colors.blue.shade200
                  : Colors.orange.shade200,
            ),
          ),
          child: Row(
            children: [
              if (isProcessing)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                  ),
                )
              else
                Icon(
                  Icons.sync,
                  color: Colors.orange.shade700,
                  size: 20,
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isProcessing
                      ? 'Syncing pending orders...'
                      : '$pendingCount order${pendingCount > 1 ? 's' : ''} pending sync',
                  style: TextStyle(
                    color: isProcessing
                        ? Colors.blue.shade700
                        : Colors.orange.shade700,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (!isProcessing && pendingCount > 0)
                IconButton(
                  icon: Icon(
                    Icons.refresh,
                    color: Colors.orange.shade700,
                    size: 20,
                  ),
                  onPressed: () {
                    offlineService.processPendingTransactions();
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Retry now',
                ),
            ],
          ),
        );
      },
    );
  }
}













