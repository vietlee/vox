class SurveyPolicy < ApplicationPolicy
  def results? = index?
  def publish?  = admin_or_owner?
  def close?    = admin_or_owner?
  def archive?  = user.admin?
  def ai_analyze? = user.admin? || user.supporter?
  def ai_report?  = user.admin?
end
