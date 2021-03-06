# Basic Marty single-page application with authentication.
#
# == Extending Marty::AuthApp
# DOCFIX
class Marty::AuthApp < Marty::SimpleApp
  # Set the Logout button if current_user is set
  def menu
    [].tap do |menu|
      user = Mcfly.whodunnit
      if !user.nil?
        menu << "->" << {
          text: user.name,
          menu: user_menu,
          name: "sign_out",
        }
      else
        menu << "->" << :sign_in
      end
    end
  end

  def user_menu
    [:sign_out]
  end

  action :sign_in do |c|
    c.icon = :door_in
  end

  action :sign_out do |c|
    c.icon = :door_out
    c.text = "Sign out #{Mcfly.whodunnit.name}" if Mcfly.whodunnit
  end

  js_configure do |c|
    c.mixin
    # FIXME: hacky -- if auth_spec_mode config is set, the JS code
    # doesn't reload the screen on login.  Is is currently needed with
    # netzke-testing.
    c.auth_spec_mode = Rails.configuration.marty.auth_spec_mode
  end

  endpoint :sign_in do |params,this|
    user = Marty::User.try_to_login(params[:login], params[:password])

    if user
      Netzke::Base.controller.set_user(user)
      this.netzke_set_result(true)
    else
      this.netzke_set_result(false)
      this.netzke_feedback("Wrong credentials")
    end
  end

  endpoint :sign_out do |params,this|
    Netzke::Base.controller.logout_user
    this.netzke_set_result(true)
  end
end
