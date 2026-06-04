import 'package:flutter/material.dart';

class QuickTransactionDropdownField extends StatelessWidget {
  const QuickTransactionDropdownField({
    required this.value,
    required this.label,
    required this.icon,
    required this.items,
    required this.onChanged,
    this.validator,
    this.menuHeight = 360,
    super.key,
  });

  final String? value;
  final String label;
  final IconData icon;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?> onChanged;
  final String? Function(String?)? validator;
  final double menuHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        labelStyle: TextStyle(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w800,
        ),
        filled: true,
        fillColor: Color.alphaBlend(
          theme.colorScheme.primary.withValues(alpha: 0.035),
          theme.colorScheme.surface,
        ),
        prefixIcon: Icon(icon, size: 20),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.2),
        ),
      ),
      menuMaxHeight: menuHeight,
      items: items,
      validator: validator,
      onChanged: onChanged,
    );
  }
}
