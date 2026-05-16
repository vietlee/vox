module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      warden = env["warden"]
      return warden.user if warden&.authenticated?(:user)
      nil
    rescue
      nil
    end
  end
end
