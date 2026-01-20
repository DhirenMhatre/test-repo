require 'securerandom'
require 'base64'

class ApiTokenManager
  def initialize
    @tokens = {}
  end

  def generate_token(user_id, scope: 'read')
    token = SecureRandom.urlsafe_base64(32)

    @tokens[token] = {
      user_id: user_id,
      scope: scope,
      created_at: Time.now,
      last_used: Time.now
    }

    token
  end

  def verify_token(token)
    token_data = @tokens[token]
    return nil unless token_data

    @tokens[token][:last_used] = Time.now
    token_data[:user_id]
  end

  def revoke_token(token)
    @tokens.delete(token)
  end

  def get_token_scope(token)
    token_data = @tokens[token]
    token_data ? token_data[:scope] : nil
  end

  def update_token_scope(token, new_scope)
    return false unless @tokens[token]
    @tokens[token][:scope] = new_scope
    true
  end

  def all_tokens_for_user(user_id)
    @tokens.select { |token, data| data[:user_id] == user_id }.keys
  end
end
