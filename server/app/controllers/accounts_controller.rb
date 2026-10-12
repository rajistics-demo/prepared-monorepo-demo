class AccountsController < ApplicationController
  MAX_LIMIT = 50

  def recently_paid
    limit = params.fetch(:limit, RecentlyPaidAccounts::DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT)
    accounts = RecentlyPaidAccounts.new(limit: limit).call
    render json: accounts.map { |a| { id: a.id, name: a.name, last_payment_at: a.last_payment_at&.iso8601 } }
  end

  def ledger
    account = Account.find(params[:id])
    render json: {
      account_id: account.id,
      balance_cents: LedgerEntry.balance_for(account.id),
      entries: LedgerEntry.running_balances(account.id)
    }
  end

  def activity
    account = Account.find(params[:id])
    events = AccountEvent.recent_for(account.id)
    render json: events.map { |e| { kind: e.kind, occurred_at: e.occurred_at.iso8601, payload: e.payload } }
  end
end
