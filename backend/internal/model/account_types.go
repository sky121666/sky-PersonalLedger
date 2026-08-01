package model

var debtAccountTypeSet = map[string]struct{}{
	"credit":        {},
	"loan":          {},
	"mortgage":      {},
	"car_loan":      {},
	"consumer_loan": {},
	"huabei":        {},
	"baitiao":       {},
	"payable":       {},
}

var debtAccountTypeValues = []string{
	"credit",
	"loan",
	"mortgage",
	"car_loan",
	"consumer_loan",
	"huabei",
	"baitiao",
	"payable",
}

func IsDebtAccountType(accountType string) bool {
	_, exists := debtAccountTypeSet[accountType]
	return exists
}

func DebtAccountTypeValues() []string {
	return append([]string(nil), debtAccountTypeValues...)
}
