CREATE INDEX IF NOT EXISTS idx_group_members_user ON group_members(user_id);
CREATE INDEX IF NOT EXISTS idx_group_members_group ON group_members(group_id);
CREATE INDEX IF NOT EXISTS idx_group_invites_group ON group_invites(group_id);
CREATE INDEX IF NOT EXISTS idx_group_invites_token ON group_invites(token);
CREATE INDEX IF NOT EXISTS idx_expenses_group_date ON expenses(group_id, expense_date DESC, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_expense_payers_user ON expense_payers(user_id);
CREATE INDEX IF NOT EXISTS idx_expense_splits_user ON expense_splits(user_id);
CREATE INDEX IF NOT EXISTS idx_expense_attachments_expense ON expense_attachments(expense_id);
CREATE INDEX IF NOT EXISTS idx_user_sessions_expire ON user_sessions(expire);
