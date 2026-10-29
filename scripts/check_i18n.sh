#!/usr/bin/env bash
# Checks that every translation key used in the Flutter apps exists in English and French,
# and that both string files have exactly the same keys.
set -euo pipefail
cd "$(dirname "$0")/.."

src=packages/babymama_core/lib/src
keys() { grep -oE "^  '[A-Za-z0-9_]+':" "$1" | sed -E "s/^  '//; s/':$//" | sort -u; }
en=$(keys $src/strings_en.dart)
fr=$(keys $src/strings_fr.dart)

status=0
missing_fr=$(comm -23 <(echo "$en") <(echo "$fr"))
missing_en=$(comm -13 <(echo "$en") <(echo "$fr"))
[ -n "$missing_fr" ] && { echo "Missing in French:"; echo "$missing_fr"; status=1; }
[ -n "$missing_en" ] && { echo "Missing in English:"; echo "$missing_en"; status=1; }

# Static keys used in code: .tr('key') and _Section('key')
used=$( { grep -rhoE "\.tr\('[a-z0-9_]+'" apps packages | sed -E "s/.*\('//; s/'$//";
          grep -rhoE "_Section\('[a-z_]+'" apps | sed -E "s/.*\('//; s/'$//"; } | sort -u)
undefined=$(comm -23 <(echo "$used") <(echo "$en"))
[ -n "$undefined" ] && { echo "Used in code but not translated:"; echo "$undefined"; status=1; }

# Dynamic key families: prefix + enum value
check_family() {
  local prefix=$1; shift
  for v in "$@"; do
    echo "$en" | grep -qx "${prefix}${v}" || { echo "Missing family key: ${prefix}${v}"; status=1; }
  done
}
check_family condition_ NEW_WITH_TAGS NEW_WITHOUT_TAGS VERY_GOOD GOOD SATISFACTORY
check_family status_ PENDING_PAYMENT CONFIRMED PREPARING READY OUT_FOR_DELIVERY DELIVERED CANCELLED REFUNDED
check_family payment_status_ UNPAID PENDING PAID FAILED REFUNDED
check_family delivery_status_ UNASSIGNED ASSIGNED ACCEPTED PICKED_UP IN_TRANSIT DELIVERED FAILED
check_family product_status_ DRAFT PENDING_REVIEW ACTIVE SOLD_OUT ARCHIVED REJECTED
check_family ticket_status_ OPEN PENDING RESOLVED CLOSED
check_family pay_ MPESA AIRTEL_MONEY CARD CASH_ON_DELIVERY
check_family sort_ newest price_asc price_desc popular
check_family movement_ RESTOCK SALE RELEASE ADJUSTMENT RETURN WOO_SYNC
check_family source_ ADMIN SELLER WOOCOMMERCE
check_family role_ CUSTOMER DRIVER SUPPORT ADMIN
check_family vehicle_ MOTORBIKE BICYCLE CAR FOOT
check_family banner_type_ PROMO NEW_ARRIVALS PRODUCT CATEGORY BUNDLE EXTERNAL
check_family no_deliveries_ available active history
check_family location_ disabled denied

if [ $status -eq 0 ]; then echo "i18n OK: $(echo "$en" | wc -l) keys in EN and FR"; fi
exit $status
