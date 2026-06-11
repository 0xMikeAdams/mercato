# Dialyzer warnings intentionally suppressed. Entries are {file, warning_type}.
# Keep this list small and documented; `list_unused_filters: true` (mix.exs) flags
# any entry that no longer matches so stale ignores don't accumulate.
[
  # Ecto.Multi.run/update fed schema structs trips Dialyzer's opaque-type analysis on
  # Ecto's internal Multi/changeset types. A well-known false positive, not a real defect.
  {"lib/mercato/orders.ex", :call_without_opaque},
  {"lib/mercato/subscriptions.ex", :call_without_opaque},

  # Defensive {:error, _} fallback clauses kept intentionally for robustness against
  # future callee changes; Dialyzer proves them unreachable given today's success typings.
  {"lib/mercato/cart.ex", :pattern_match_cov},
  {"lib/mercato/controllers/cart_controller.ex", :pattern_match_cov},
  {"lib/mercato/referral_controller.ex", :pattern_match_cov}
]
