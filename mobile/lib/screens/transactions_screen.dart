import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/transaction_service.dart';
import '../models/transaction.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final TransactionService _service = TransactionService();
  final ScrollController _scrollController = ScrollController();

  List<Transaction> _transactions = [];
  bool _loading = false;
  bool _hasMore = true;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _loadTransactions();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadTransactions() async {
    setState(() => _loading = true);
    try {
      final data = await _service.getList(page: 1, pageSize: 20);
      setState(() {
        _transactions = data.list;
        _hasMore = data.hasMore;
        _page = 1;
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      _page++;
      final data = await _service.getList(page: _page, pageSize: 20);
      setState(() {
        _transactions.addAll(data.list);
        _hasMore = data.hasMore;
      });
    } catch (_) {
      _page--;
    } finally {
      setState(() => _loading = false);
    }
  }

  String _formatDate(String date) {
    final dt = DateTime.parse(date);
    return DateFormat('M月d日').format(dt);
  }

  String _formatMoney(double value) {
    return '¥${value.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('交易明细'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadTransactions,
        child: _transactions.isEmpty && !_loading
            ? const Center(child: Text('暂无交易记录', style: TextStyle(color: Colors.grey)))
            : ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _transactions.length + (_loading ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _transactions.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final tx = _transactions[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Color(int.parse(tx.categoryColor.replaceFirst('#', '0xFF'))).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: Text(tx.categoryEmoji, style: const TextStyle(fontSize: 20)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tx.categoryName.isEmpty ? '未分类' : tx.categoryName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                _formatDate(tx.transactionDate),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${tx.isIncome ? '+' : '-'}${_formatMoney(tx.amount)}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: tx.isIncome ? const Color(0xFF34C759) : Colors.black,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
