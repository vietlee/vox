module ApplicationCable
  class Connection < ActionCable::Connection::Base
    # A connection may be a teacher (User, web admin), a learner (Vox Learner
    # app), or anonymous (e.g. public vote participants). We identify whoever
    # is signed in and let each channel enforce its own authorization — we do
    # NOT reject anonymous connections here, since some channels are public.
    identified_by :current_user, :current_learner

    def connect
      self.current_user    = find_verified(:user)
      self.current_learner = find_verified(:learner)
    end

    # The signed-in actor (User or Learner), or nil when anonymous.
    def actor
      current_user || current_learner
    end

    private

    def find_verified(scope)
      warden = env["warden"]
      return warden.user(scope) if warden&.authenticated?(scope)
      nil
    rescue
      nil
    end
  end
end
