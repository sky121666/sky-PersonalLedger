package service

import (
	"errors"
	"strings"
	"time"

	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
)

var (
	ErrFamilyMemberNotFound  = errors.New("family member not found")
	ErrFamilyMemberNameEmpty = errors.New("family member name is required")
)

type FamilyMemberService struct {
	repo         *repository.FamilyMemberRepository
	txRepo       *repository.TransactionRepository
	categoryRepo *repository.CategoryRepository
}

func NewFamilyMemberService(repo *repository.FamilyMemberRepository, txRepos ...*repository.TransactionRepository) *FamilyMemberService {
	var txRepo *repository.TransactionRepository
	if len(txRepos) > 0 {
		txRepo = txRepos[0]
	}
	return &FamilyMemberService{repo: repo, txRepo: txRepo}
}

func (s *FamilyMemberService) WithCategoryRepository(categoryRepo *repository.CategoryRepository) *FamilyMemberService {
	s.categoryRepo = categoryRepo
	return s
}

type CreateFamilyMemberRequest struct {
	Name         string `json:"name" binding:"required"`
	Relationship string `json:"relationship"`
	Avatar       string `json:"avatar"`
	Color        string `json:"color"`
}

type UpdateFamilyMemberRequest struct {
	Name         string `json:"name" binding:"required"`
	Relationship string `json:"relationship"`
	Avatar       string `json:"avatar"`
	Color        string `json:"color"`
	SortOrder    *int   `json:"sort_order"`
	IsDefault    *bool  `json:"is_default"`
	IsEnabled    *bool  `json:"is_enabled"`
}

func (s *FamilyMemberService) Create(userID uint, req CreateFamilyMemberRequest) (*model.FamilyMember, error) {
	name := strings.TrimSpace(req.Name)
	if name == "" {
		return nil, ErrFamilyMemberNameEmpty
	}

	count, err := s.repo.CountByUserID(userID)
	if err != nil {
		return nil, err
	}

	member := &model.FamilyMember{
		UserID:       userID,
		Name:         name,
		Relationship: strings.TrimSpace(req.Relationship),
		Avatar:       strings.TrimSpace(req.Avatar),
		Color:        strings.TrimSpace(req.Color),
		SortOrder:    int(count),
		IsDefault:    count == 0,
		IsEnabled:    true,
	}

	if err := s.repo.Create(member); err != nil {
		return nil, err
	}
	return s.repo.GetByID(member.ID)
}

func (s *FamilyMemberService) GetByID(id string, userID uint) (*model.FamilyMember, error) {
	member, err := s.repo.GetByID(id)
	if err != nil || member.UserID != userID {
		return nil, ErrFamilyMemberNotFound
	}
	return member, nil
}

func (s *FamilyMemberService) List(userID uint) ([]model.FamilyMember, error) {
	return s.repo.GetByUserID(userID)
}

func (s *FamilyMemberService) Update(id string, userID uint, req UpdateFamilyMemberRequest) (*model.FamilyMember, error) {
	member, err := s.GetByID(id, userID)
	if err != nil {
		return nil, err
	}

	name := strings.TrimSpace(req.Name)
	if name == "" {
		return nil, ErrFamilyMemberNameEmpty
	}

	member.Name = name
	member.Relationship = strings.TrimSpace(req.Relationship)
	member.Avatar = strings.TrimSpace(req.Avatar)
	member.Color = strings.TrimSpace(req.Color)
	if req.SortOrder != nil {
		member.SortOrder = *req.SortOrder
	}
	if req.IsEnabled != nil {
		member.IsEnabled = *req.IsEnabled
	}
	if req.IsDefault != nil {
		member.IsDefault = *req.IsDefault
		if *req.IsDefault {
			if err := s.repo.ClearDefault(userID, member.ID); err != nil {
				return nil, err
			}
			member.IsEnabled = true
		}
	}

	if err := s.repo.Update(member); err != nil {
		return nil, err
	}
	return s.repo.GetByID(id)
}

func (s *FamilyMemberService) Delete(id string, userID uint) error {
	member, err := s.GetByID(id, userID)
	if err != nil {
		return err
	}
	member.IsEnabled = false
	member.IsDefault = false
	return s.repo.Update(member)
}

type FamilySummaryResponse struct {
	Month        string                `json:"month"`
	Period       string                `json:"period"`
	Label        string                `json:"label"`
	TotalExpense float64               `json:"total_expense"`
	Members      []FamilyMemberSummary `json:"members"`
}

type FamilyMemberSummary struct {
	MemberID     string  `json:"member_id"`
	Name         string  `json:"name"`
	Relationship string  `json:"relationship"`
	Color        string  `json:"color"`
	ExpenseTotal float64 `json:"expense_total"`
	Count        int     `json:"count"`
}

type FamilyStatisticsResponse struct {
	Month        string                   `json:"month"`
	Period       string                   `json:"period"`
	Label        string                   `json:"label"`
	TotalExpense float64                  `json:"total_expense"`
	Members      []FamilyStatisticsMember `json:"members"`
}

type FamilyStatisticsMember struct {
	MemberID     string                     `json:"member_id"`
	Name         string                     `json:"name"`
	Relationship string                     `json:"relationship"`
	Color        string                     `json:"color"`
	ExpenseTotal float64                    `json:"expense_total"`
	Count        int                        `json:"count"`
	Categories   []FamilyStatisticsCategory `json:"categories"`
}

type FamilyStatisticsCategory struct {
	CategoryID string  `json:"category_id"`
	Name       string  `json:"name"`
	Color      string  `json:"color"`
	Amount     float64 `json:"amount"`
	Count      int     `json:"count"`
}

func (s *FamilyMemberService) Summary(userID uint, month string) (*FamilySummaryResponse, error) {
	return s.SummaryByPeriod(userID, month, "")
}

func (s *FamilyMemberService) SummaryByPeriod(userID uint, month, period string) (*FamilySummaryResponse, error) {
	statRange, err := statisticsDateRange(month, period)
	if err != nil {
		return nil, err
	}

	response := &FamilySummaryResponse{
		Month:   familyRangeMonthLabel(statRange),
		Period:  statRange.Period,
		Label:   familyRangeDisplayLabel(statRange),
		Members: []FamilyMemberSummary{},
	}
	if s.txRepo == nil {
		return response, nil
	}

	members, err := s.repo.GetByUserID(userID)
	if err != nil {
		return nil, err
	}
	memberByID := make(map[string]model.FamilyMember, len(members))
	for _, member := range members {
		memberByID[member.ID] = member
	}

	sums, err := s.txRepo.SumExpenseByMember(userID, statRange.Start, statRange.End)
	if err != nil {
		return nil, err
	}
	for _, sum := range sums {
		response.TotalExpense += sum.Total
		if sum.MemberID == "" {
			continue
		}
		member := memberByID[sum.MemberID]
		response.Members = append(response.Members, FamilyMemberSummary{
			MemberID:     sum.MemberID,
			Name:         member.Name,
			Relationship: member.Relationship,
			Color:        member.Color,
			ExpenseTotal: sum.Total,
			Count:        sum.Count,
		})
	}
	return response, nil
}

func (s *FamilyMemberService) Statistics(userID uint, month string) (*FamilyStatisticsResponse, error) {
	return s.StatisticsByPeriod(userID, month, "")
}

func (s *FamilyMemberService) StatisticsByPeriod(userID uint, month, period string) (*FamilyStatisticsResponse, error) {
	statRange, err := statisticsDateRange(month, period)
	if err != nil {
		return nil, err
	}

	response := &FamilyStatisticsResponse{
		Month:   familyRangeMonthLabel(statRange),
		Period:  statRange.Period,
		Label:   familyRangeDisplayLabel(statRange),
		Members: []FamilyStatisticsMember{},
	}
	if s.txRepo == nil {
		return response, nil
	}

	members, err := s.repo.GetByUserID(userID)
	if err != nil {
		return nil, err
	}
	memberByID := make(map[string]model.FamilyMember, len(members))
	for _, member := range members {
		memberByID[member.ID] = member
	}

	categoryByID := map[string]model.Category{}
	if s.categoryRepo != nil {
		categories, err := s.categoryRepo.GetByUserID(userID, "expense")
		if err != nil {
			return nil, err
		}
		for _, category := range categories {
			categoryByID[category.ID] = category
		}
	}

	sums, err := s.txRepo.SumExpenseByMember(userID, statRange.Start, statRange.End)
	if err != nil {
		return nil, err
	}
	memberIndex := make(map[string]int, len(sums))
	for _, sum := range sums {
		response.TotalExpense += sum.Total
		if sum.MemberID == "" {
			continue
		}
		member := memberByID[sum.MemberID]
		memberIndex[sum.MemberID] = len(response.Members)
		response.Members = append(response.Members, FamilyStatisticsMember{
			MemberID:     sum.MemberID,
			Name:         member.Name,
			Relationship: member.Relationship,
			Color:        member.Color,
			ExpenseTotal: sum.Total,
			Count:        sum.Count,
			Categories:   []FamilyStatisticsCategory{},
		})
	}

	categorySums, err := s.txRepo.SumExpenseByMemberAndCategory(userID, statRange.Start, statRange.End)
	if err != nil {
		return nil, err
	}
	for _, sum := range categorySums {
		if sum.MemberID == "" {
			continue
		}
		index, ok := memberIndex[sum.MemberID]
		if !ok {
			continue
		}
		category := categoryByID[sum.CategoryID]
		response.Members[index].Categories = append(
			response.Members[index].Categories,
			FamilyStatisticsCategory{
				CategoryID: sum.CategoryID,
				Name:       category.Name,
				Color:      category.Color,
				Amount:     sum.Total,
				Count:      sum.Count,
			},
		)
	}
	return response, nil
}

func familySummaryMonthRange(month string) (time.Time, time.Time, string, error) {
	if strings.TrimSpace(month) == "" {
		now := time.Now()
		month = now.Format("2006-01")
	}
	startDate, err := time.ParseInLocation("2006-01", month, time.Local)
	if err != nil {
		return time.Time{}, time.Time{}, "", err
	}
	endDate := startDate.AddDate(0, 1, 0).Add(-time.Second)
	return startDate, endDate, startDate.Format("2006-01"), nil
}

func familyRangeMonthLabel(statRange statisticsRange) string {
	switch statRange.Period {
	case "year":
		return statRange.Start.Format("2006")
	case "history":
		return "往年"
	default:
		return statRange.Start.Format("2006-01")
	}
}

func familyRangeDisplayLabel(statRange statisticsRange) string {
	switch statRange.Period {
	case "year":
		return statRange.Start.Format("2006年")
	case "history":
		return "往年"
	default:
		return statRange.Start.Format("2006年1月")
	}
}
