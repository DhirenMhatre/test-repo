require 'securerandom'
require 'digest'

class SessionStore
  def initialize(timeout_seconds: 3600)
    @sessions = {}
    @timeout = timeout_seconds
    @counter = 0
  end

  def create(user_id, metadata = {})
    token = generate_token(user_id)

    @sessions[token] = {
      user_id: user_id,
      created_at: Time.now,
      metadata: metadata
    }

    token
  end

  def validate(token)
    session = @sessions[token]
    return nil unless session

    if expired?(session)
      @sessions.delete(token)
      return nil
    end

    session[:user_id]
  end

  def destroy(token)
    @sessions.delete(token)
  end

  def all_sessions
    @sessions.dup
  end

  private

  def generate_token(user_id)
    @counter += 1
    timestamp = Time.now.to_i
    random = SecureRandom.hex(16)
    "#{user_id}_#{timestamp}_#{@counter}_#{random}"
  end

  def expired?(session)
    Time.now - session[:created_at] > @timeout
  end
end
