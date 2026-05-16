class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user   = user
    @record = record
  end

  def index?   = user.admin? || user.supporter?
  def show?    = user.admin? || user.supporter?
  def create?  = user.admin? || user.supporter?
  def update?  = admin_or_owner?
  def destroy? = admin_or_owner?

  private

  def admin_or_owner?
    user.admin? || record.try(:user_id) == user.id
  end

  class Scope
    def initialize(user, scope)
      @user  = user
      @scope = scope
    end

    def resolve
      if @user.admin?
        @scope.where(workspace: @user.workspace)
      elsif @user.supporter?
        @scope.where(workspace: @user.workspace, user: @user)
      else
        @scope.none
      end
    end
  end
end
