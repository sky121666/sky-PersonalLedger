#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${LEDGER_SHOWCASE_BASE_URL:-http://127.0.0.1:18080}"
PASSWORD="${LEDGER_SHOWCASE_PASSWORD:-}"
AI_PORT="${LEDGER_SHOWCASE_AI_PORT:-18081}"
ALLOW_REMOTE="${LEDGER_SHOWCASE_ALLOW_REMOTE:-0}"

if [[ -z "$PASSWORD" ]]; then
  echo "LEDGER_SHOWCASE_PASSWORD is required; no default password is provided." >&2
  exit 1
fi
if (( ${#PASSWORD} < 8 )); then
  echo "LEDGER_SHOWCASE_PASSWORD must be at least 8 characters." >&2
  exit 1
fi
if [[ ! "$BASE_URL" =~ ^https?://(127\.0\.0\.1|localhost|\[::1\])(:[0-9]+)?(/|$) && "$ALLOW_REMOTE" != "1" ]]; then
  echo "Refusing to seed a non-loopback server without LEDGER_SHOWCASE_ALLOW_REMOTE=1." >&2
  exit 1
fi

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_command curl
require_command jq
require_command python3

api() {
  local method="$1"
  local path="$2"
  local body="${3:-}"
  if [[ -n "$body" ]]; then
    curl -fsS -X "$method" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      "$BASE_URL/api/v1$path" \
      -d "$body"
  else
    curl -fsS -X "$method" \
      -H "Authorization: Bearer $TOKEN" \
      "$BASE_URL/api/v1$path"
  fi
}

ensure_item() {
  local list_path="$1"
  local create_path="$2"
  local name="$3"
  local body="$4"
  local existing
  existing="$(api GET "$list_path" | jq -r --arg name "$name" '(.data | if type == "object" and has("list") then .list else . end // [])[]? | select(.name == $name) | .id' | head -1)"
  if [[ -n "$existing" ]]; then
    echo "$existing"
  else
    api POST "$create_path" "$body" | jq -r '.data.id'
  fi
}

ensure_transaction() {
  local remark="$1"
  local body="$2"
  local existing
  existing="$(api GET "/transactions?page=1&page_size=200" | jq -r --arg remark "$remark" '.data.list[]? | select(.remark == $remark) | .id' | head -1)"
  if [[ -n "$existing" ]]; then
    echo "$existing"
  else
    api POST /transactions "$body" | jq -r '.data.id'
  fi
}

ensure_lending() {
  local contact_name="$1"
  local body="$2"
  local existing
  existing="$(api GET "/lendings?include_settled=true" | jq -r --arg name "$contact_name" '.data[]? | select(.contact_name == $name) | .id' | head -1)"
  if [[ -n "$existing" ]]; then
    echo "$existing"
  else
    api POST /lendings "$body" | jq -r '.data.id'
  fi
}

start_fake_ai() {
  if lsof -iTCP:"$AI_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    return
  fi
  python3 - "$AI_PORT" <<'PY' &
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

port = int(sys.argv[1])

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("content-length", "0"))
        _ = self.rfile.read(length)
        content = json.dumps({
            "summary": "本月现金流稳定，家庭餐饮和交通支出占比较高，预算仍有余量。",
            "highlights": ["工资收入入账", "房贷提醒已建立", "借贷往来有进行中记录"],
            "risks": ["餐饮预算接近提醒线", "信用卡还款日临近"],
            "actions": ["保留每周复盘", "优先清理高息负债", "减少零散消费"]
        }, ensure_ascii=False)
        body = json.dumps({"choices": [{"message": {"content": content}}]}, ensure_ascii=False).encode()
        self.send_response(200)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *_):
        pass

HTTPServer(("127.0.0.1", port), Handler).serve_forever()
PY
  sleep 0.5
}

status="$(curl -fsS "$BASE_URL/api/v1/auth/status" | jq -r '.data.initialized')"
if [[ "$status" != "true" ]]; then
  TOKEN="$(curl -fsS -X POST -H "Content-Type: application/json" "$BASE_URL/api/v1/auth/init" -d "$(jq -nc --arg password "$PASSWORD" '{password:$password}')" | jq -r '.data.access_token')"
else
  TOKEN="$(curl -fsS -X POST -H "Content-Type: application/json" "$BASE_URL/api/v1/auth/login" -d "$(jq -nc --arg password "$PASSWORD" '{password:$password}')" | jq -r '.data.access_token')"
fi

if [[ -z "$TOKEN" || "$TOKEN" == "null" ]]; then
  echo "Unable to authenticate to $BASE_URL" >&2
  exit 1
fi

me="$(ensure_item /family/members /family/members "我" '{"name":"我","relationship":"self","color":"#0F766E","avatar":"person"}')"
partner="$(ensure_item /family/members /family/members "家人" '{"name":"家人","relationship":"family","color":"#2563EB","avatar":"family"}')"
child="$(ensure_item /family/members /family/members "孩子" '{"name":"孩子","relationship":"child","color":"#EA580C","avatar":"child"}')"

cash="$(ensure_item "/accounts?include_archived=true" /accounts "现金" '{"name":"现金","type":"cash","initial_balance":1200,"icon":"cash","color":"#0F766E","remark":"展示数据"}')"
bank="$(ensure_item "/accounts?include_archived=true" /accounts "招商银行卡" '{"name":"招商银行卡","type":"bank_card","initial_balance":28600,"icon":"bank_card","color":"#2563EB","remark":"工资与日常支出"}')"
alipay="$(ensure_item "/accounts?include_archived=true" /accounts "支付宝" '{"name":"支付宝","type":"alipay","initial_balance":3680,"icon":"wallet","color":"#0891B2","remark":"线上消费"}')"
credit="$(ensure_item "/accounts?include_archived=true" /accounts "招行信用卡" '{"name":"招行信用卡","type":"credit","initial_balance":4280,"icon":"credit","color":"#DC2626","payment_day":18,"billing_day":5,"credit_limit":30000,"remark":"展示数据"}')"
mortgage="$(ensure_item "/accounts?include_archived=true" /accounts "房贷" '{"name":"房贷","type":"mortgage","initial_balance":520000,"icon":"mortgage","color":"#EA580C","payment_day":20,"interest_rate":3.65,"start_date":"2024-01-01","target_date":"2044-01-01","remark":"长期负债"}')"
fund="$(ensure_item "/accounts?include_archived=true" /accounts "基金账户" '{"name":"基金账户","type":"fund","initial_balance":42000,"icon":"investment","color":"#7C3AED","remark":"长期资产"}')"

salary="$(ensure_item "/categories?type=income" /categories "工资" '{"name":"工资","type":"income","icon":"work","color":"#059669"}')"
bonus="$(ensure_item "/categories?type=income" /categories "副业" '{"name":"副业","type":"income","icon":"bolt","color":"#14B8A6"}')"
food="$(ensure_item "/categories?type=expense" /categories "餐饮" '{"name":"餐饮","type":"expense","icon":"restaurant","color":"#EF4444"}')"
transport="$(ensure_item "/categories?type=expense" /categories "交通" '{"name":"交通","type":"expense","icon":"directions_car","color":"#F59E0B"}')"
housing="$(ensure_item "/categories?type=expense" /categories "居住" '{"name":"居住","type":"expense","icon":"home","color":"#2563EB"}')"
shopping="$(ensure_item "/categories?type=expense" /categories "购物" '{"name":"购物","type":"expense","icon":"shopping_bag","color":"#EC4899"}')"
education="$(ensure_item "/categories?type=expense" /categories "教育" '{"name":"教育","type":"expense","icon":"school","color":"#7C3AED"}')"
medical="$(ensure_item "/categories?type=expense" /categories "医疗" '{"name":"医疗","type":"expense","icon":"local_hospital","color":"#10B981"}')"

tag_daily="$(ensure_item /tags /tags "日常" '{"name":"日常","color":"#0F766E","icon":"tag"}')"
tag_family="$(ensure_item /tags /tags "家庭" '{"name":"家庭","color":"#2563EB","icon":"group"}')"
tag_fixed="$(ensure_item /tags /tags "固定支出" '{"name":"固定支出","color":"#EA580C","icon":"repeat"}')"

today="$(date +%Y-%m-%d)"
month_start="$(date +%Y-%m-01)"
last_week="$(date -v-7d +%Y-%m-%d 2>/dev/null || date -d '7 days ago' +%Y-%m-%d)"

ensure_transaction "SHOWCASE 工资收入" "$(jq -nc --arg account "$bank" --arg category "$salary" --arg member "$me" --arg date "$month_start" '{type:"income",amount:18500,account_id:$account,category_id:$category,member_id:$member,paid_by_member_id:$member,transaction_date:$date,remark:"SHOWCASE 工资收入"}')" >/dev/null
ensure_transaction "SHOWCASE 副业项目款" "$(jq -nc --arg account "$alipay" --arg category "$bonus" --arg member "$me" --arg date "$last_week" '{type:"income",amount:3200,account_id:$account,category_id:$category,member_id:$member,paid_by_member_id:$member,transaction_date:$date,remark:"SHOWCASE 副业项目款"}')" >/dev/null
ensure_transaction "SHOWCASE 家庭晚餐" "$(jq -nc --arg account "$alipay" --arg category "$food" --arg member "$partner" --arg payer "$me" --argjson tags "[\"$tag_daily\",\"$tag_family\"]" --arg date "$today" '{type:"expense",amount:286.5,account_id:$account,category_id:$category,member_id:$member,paid_by_member_id:$payer,tags:($tags|tojson),transaction_date:$date,remark:"SHOWCASE 家庭晚餐"}')" >/dev/null
ensure_transaction "SHOWCASE 地铁通勤" "$(jq -nc --arg account "$cash" --arg category "$transport" --arg member "$me" --arg date "$today" '{type:"expense",amount:18,account_id:$account,category_id:$category,member_id:$member,paid_by_member_id:$member,transaction_date:$date,remark:"SHOWCASE 地铁通勤"}')" >/dev/null
ensure_transaction "SHOWCASE 房贷月供" "$(jq -nc --arg account "$bank" --arg category "$housing" --arg member "$me" --argjson tags "[\"$tag_fixed\"]" --arg date "$today" '{type:"expense",amount:4200,account_id:$account,category_id:$category,member_id:$member,paid_by_member_id:$member,tags:($tags|tojson),transaction_date:$date,remark:"SHOWCASE 房贷月供"}')" >/dev/null
ensure_transaction "SHOWCASE 儿童课程" "$(jq -nc --arg account "$credit" --arg category "$education" --arg member "$child" --arg payer "$partner" --arg date "$last_week" '{type:"expense",amount:980,account_id:$account,category_id:$category,member_id:$member,paid_by_member_id:$payer,transaction_date:$date,remark:"SHOWCASE 儿童课程"}')" >/dev/null
ensure_transaction "SHOWCASE 家庭药品" "$(jq -nc --arg account "$alipay" --arg category "$medical" --arg member "$partner" --arg payer "$partner" --arg date "$last_week" '{type:"expense",amount:168.8,account_id:$account,category_id:$category,member_id:$member,paid_by_member_id:$payer,transaction_date:$date,remark:"SHOWCASE 家庭药品"}')" >/dev/null
ensure_transaction "SHOWCASE 银行转入基金账户" "$(jq -nc --arg account "$bank" --arg to "$fund" --arg date "$today" '{type:"transfer",amount:3000,account_id:$account,to_account_id:$to,transaction_date:$date,remark:"SHOWCASE 银行转入基金账户"}')" >/dev/null

api POST /budgets/total '{"amount":12000,"alert_threshold":80}' >/dev/null
api POST /budgets/category "$(jq -nc --arg id "$food" '{category_id:$id,amount:2600,alert_threshold:80}')" >/dev/null
api POST /budgets/category "$(jq -nc --arg id "$transport" '{category_id:$id,amount:900,alert_threshold:75}')" >/dev/null
api POST /budgets/category "$(jq -nc --arg id "$education" '{category_id:$id,amount:1800,alert_threshold:85}')" >/dev/null
api POST /budgets/total "$(jq -nc --arg id "$child" '{member_id:$id,amount:2600,alert_threshold:80}')" >/dev/null

ensure_item /templates /templates "午餐模板" "$(jq -nc --arg account "$alipay" --arg category "$food" '{name:"午餐模板",type:"expense",amount:38,account_id:$account,category_id:$category,remark:"工作日午餐"}')" >/dev/null
ensure_item /templates /templates "地铁模板" "$(jq -nc --arg account "$cash" --arg category "$transport" '{name:"地铁模板",type:"expense",amount:6,account_id:$account,category_id:$category,remark:"通勤"}')" >/dev/null

ensure_item /reminders /reminders "招行信用卡还款" "$(jq -nc --arg account "$credit" '{name:"招行信用卡还款",account_id:$account,loan_type:"credit_card",payment_day:18,billing_day:5,advance_days:3,amount:4280,current_balance:4280,color:"#DC2626",remark:"展示提醒"}')" >/dev/null
ensure_item /reminders /reminders "房贷月供提醒" "$(jq -nc --arg account "$mortgage" '{name:"房贷月供提醒",account_id:$account,loan_type:"mortgage",payment_day:20,advance_days:5,amount:4200,current_balance:520000,interest_rate:3.65,color:"#EA580C",remark:"展示提醒"}')" >/dev/null

ensure_lending "张三" "$(jq -nc --arg account "$bank" '{type:"lend_out",contact_name:"张三",contact_phone:"13800000001",contact_remark:"朋友",principal:5000,interest_rate:0,lend_date:"2026-06-02",due_date:"2026-07-02",account_id:$account,remark:"SHOWCASE 借出周转",create_transaction:true}')" >/dev/null
ensure_lending "李四" "$(jq -nc --arg account "$bank" '{type:"borrow_in",contact_name:"李四",contact_phone:"13800000002",contact_remark:"亲友",principal:8000,interest_rate:3.5,lend_date:"2026-05-20",due_date:"2026-08-20",account_id:$account,remark:"SHOWCASE 临时借入",create_transaction:true}')" >/dev/null

start_fake_ai
provider="$(ensure_item /ai/providers /ai/providers "本地展示 AI" "$(jq -nc --arg base "http://127.0.0.1:$AI_PORT" '{name:"本地展示 AI",provider_type:"openai_compatible",base_url:$base,api_key:"showcase-key",model:"showcase-model",enabled:true}')")"
api POST /ai/reports/generate "$(jq -nc --arg provider "$provider" '{report_type:"weekly",provider_id:$provider,period_start:"2026-06-01",period_end:"2026-06-07",mask_names:false}')" >/dev/null || true

echo "Showcase data ready:"
echo "accounts=$(api GET '/accounts?include_archived=true' | jq '.data.list | length')"
echo "transactions=$(api GET '/transactions?page=1&page_size=200' | jq '.data.total')"
echo "budgets=$(api GET '/budgets' | jq '[.data.total_budget, (.data.category_budgets[]?), (.data.member_budgets[]?)] | map(select(. != null)) | length')"
echo "lendings=$(api GET '/lendings?include_settled=true' | jq '.data | length')"
echo "reminders=$(api GET '/reminders' | jq '.data | length')"
echo "ai_reports=$(api GET '/ai/reports' | jq '.data | length')"
