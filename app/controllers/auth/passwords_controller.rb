class Auth::PasswordsController < Devise::PasswordsController
  def create
    self.resource = resource_class.send_reset_password_instructions(resource_params)
    yield resource if block_given?

    if successfully_sent?(resource)
      # Stay on the same page with a success flag instead of redirecting
      @email_sent = true
      @submitted_email = resource_params[:email]
      render :new
    else
      render :new
    end
  end
end
