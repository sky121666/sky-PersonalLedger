const debtAccountTypes = <String>{
  'credit',
  'loan',
  'mortgage',
  'car_loan',
  'consumer_loan',
  'huabei',
  'baitiao',
  'payable',
};

bool isDebtAccountType(String type) => debtAccountTypes.contains(type);
