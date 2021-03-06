class ApplicationController < ActionController::Base
  helper :all

  protect_from_forgery
  rescue_from ActionController::InvalidAuthenticityToken, :with => :session_expired

  include AuthenticatedSystem
  include ExceptionNotifiable
  include FilenameUtils
  include SslRequirement
  
  filter_parameter_logging :password

  if (RAILS_ENV == 'production')
    SslRequirement.ssl_all = true
  else
    SslRequirement.disable_ssl_check = true
  end

  require 'csv.rb'
  require 'string_extras.rb'
  require 'date_time_extras.rb'

  # Session keys
  #  :cid               id of logged in user; if absent, nobody logged in
  #  :return_to         route params (for url_for) to return to after valid login
  #  :admin_disabled    admin is logged in but wants to see regular patron view. Causes is_admin, etc to return nil
  #  :checkout_in_progress  true if cart holds valid-looking order, which should be displayed throughout checkout flow
  #  :cart              ID of the order in progress (BUG: redundant with checkout_in_progress??)
  #  :exists            true the first time it's called on a session (for displaying login messages); false thereafter
  #                        (BUG: logic should be moved to the session create logic for interactive login)

  def session_expired
    render :template => 'messages/session_expired', :layout => 'application', :status => 400
    true
  end

  def reset_session # work around session reset bug in rails 2.3.5
    ActiveRecord::Base.connection.execute("DELETE FROM sessions WHERE session_id = '#{request.session_options[:id]}'")
  end

  def redirect_with(path,parms)
    [:alert, :notice].each { |key| flash[key] = parms[key] }
    redirect_to path
  end
  
  # set_globals tries to set globals based on current_user, among other things.
  before_filter :set_globals

  def set_globals
    @gCart = find_cart
    @gCheckoutInProgress = !@gCart.cart_empty?
    @gAdminDisplay = is_staff && !session.has_key?(:admin_disabled)
    true
  end


  def reset_shopping           # called as a filter
    @cart = find_cart
    @cart.empty_cart!
    session.delete(:promo_code)
    session.delete(:cart)
    set_checkout_in_progress(false)
    true
  end

  # a generic filter that can be used by any RESTful controller that checks
  # there's at least one instance of the model in the DB

  def has_at_least_one
    contr = self.controller_name
    klass = Kernel.const_get(contr.singularize.camelize)
    unless klass.find(:first)
      flash[:alert] = "You have not set up any #{contr} yet."
      redirect_to :action => 'new'
    end
  end

  def set_checkout_in_progress(val = true)
    if val
      session[:checkout_in_progress] = val
    else
      session.delete(:checkout_in_progress)
    end
    @gCheckoutInProgress = val
  end

  # Store the action to return to, or URI of the current request if no action given.
  # We can return to this location by calling #redirect_after_login.
  def return_after_login(route_params)
    session[:return_to] = route_params
  end

  def redirect_after_login(customer)
    redirect_to ((r = session[:return_to]) ?
      r.merge(:customer_id => customer) :
      customer_path(customer))
  end

  def find_cart
    Order.find_by_id(session[:cart]) || Order.new
  end

  # setup session etc. for an "external" login, eg by a daemon
  def login_from_external(c)
    session[:cid] = c.id
  end

  # filter that requires user to login before accessing account

  def is_logged_in
    unless logged_in?
      flash[:notice] = "Please log in or create an account in order to view this page."
      redirect_to login_path
      nil
    else
      current_user
    end
  end

  def temporarily_unavailable
    flash[:alert] = "Sorry, this function is temporarily unavailable."
    redirect_to :back
  end

  %w(staff walkup boxoffice boxoffice_manager admin).each do |r|
    define_method "is_#{r}" do
      !session[:admin_disabled] && current_user && current_user.send("is_#{r}")
    end
    define_method "is_#{r}_filter" do
      redirect_with(login_path, :alert => "You must have at least #{ActiveSupport::Inflector.humanize(r)} privilege for this action.") unless
        !session[:admin_disabled] && current_user && current_user.send("is_#{r}")
    end
  end

  def download_to_excel(output,filename="data",timestamp=true)
    (filename << "_" << Time.now.strftime("%Y_%m_%d")) if timestamp
    send_data(output,:type => (request.user_agent =~ /windows/i ?
                               'application/vnd.ms-excel' : 'text/csv'),
              :filename => "#{filename}.csv")
  end

  def email_confirmation(method,*args)
    flash[:notice] ||= ""
    customer = *args.first
    addr = customer.email
    if customer.valid_email_address?
      begin
        Mailer.send("deliver_"<< method.to_s,*args)
        flash[:notice] << " An email confirmation was sent to #{addr}.  If you don't receive it in a few minutes, please make sure 'audience1st.com' is on your trusted senders list, or the confirmation email may end up in your Junk Mail or Spam folder."
        logger.info("Confirmation email sent to #{addr}")
      rescue Exception => e
        flash[:notice] << " Your transaction was successful, but we couldn't "
        flash[:notice] << "send an email confirmation to #{addr}."
        logger.error("Emailing #{addr}: #{e.message} \n #{e.backtrace}")
      end
    else
      flash[:notice] << " Email confirmation was NOT sent because there isn't"
      flash[:notice] << " a valid email address in your Contact Info."
    end
  end

  def create_session(u = nil)
    logout_keeping_session!
    @user = u || yield(params)
    if @user && @user.errors.empty?
      # Protects against session fixation attacks, causes request forgery
      # protection if user resubmits an earlier form using back
      # button. Uncomment if you understand the tradeoffs.
      # reset_session
      self.current_user = @user
      # if user is an admin, enable admin privs
      @user.update_attribute(:last_login,Time.now)
      # 'remember me' checked?
      new_cookie_flag = (params[:remember_me] == "1")
      handle_remember_cookie! new_cookie_flag
      # finally: reset all store-related session state UNLESS the login
      # was performed as part of a checkout flow
      reset_shopping unless @gCheckoutInProgress
      redirect_after_login(@user)
    end
  end

end

