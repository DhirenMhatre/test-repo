class AuthorizationManager
  ROLE_HIERARCHY = {
    'admin' => 3,
    'developer' => 2,
    'viewer' => 1
  }.freeze

  def initialize
    @permissions_cache = {}
  end

  def can_access?(user_role, required_role)
    user_level = ROLE_HIERARCHY[user_role] || 0
    required_level = ROLE_HIERARCHY[required_role] || 0

    user_level >= required_level
  end

  def can_perform?(user_role, action)
    case action
    when 'read'
      ['admin', 'developer', 'viewer'].include?(user_role)
    when 'write'
      ['admin', 'developer'].include?(user_role)
    when 'delete'
      user_role == 'admin'
    when 'manage_users'
      user_role == 'admin'
    else
      false
    end
  end

  def grant_permission(user_id, resource_id)
    @permissions_cache[user_id] ||= []
    @permissions_cache[user_id] << resource_id unless @permissions_cache[user_id].include?(resource_id)
  end

  def has_permission?(user_id, resource_id)
    permissions = @permissions_cache[user_id]
    return false unless permissions

    permissions.include?(resource_id)
  end

  def revoke_permission(user_id, resource_id)
    return unless @permissions_cache[user_id]
    @permissions_cache[user_id].delete(resource_id)
  end
end
