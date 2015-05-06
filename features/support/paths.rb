module NavigationHelpers
  def underscorize(str) ;  str.downcase.gsub(/ /,'_') ; end
  # Maps a name to a path. Used by the
  #
  #   When /^I go to (.+)$/ do |page_name|
  #
  # step definition in webrat_steps.rb
  #
  def path_to(page_name)
    if page_name =~ /for customer "(.*) (.*)"/
      @customer = Customer.find_by_first_name_and_last_name!($1, $2)
    end
    case page_name
    when /login page/i              then login_path
    when /login with secret question page/i then new_from_secret_session_path
    when /change secret question page/      then change_secret_question_customer_path(@customer)
    when /home page/                        then customer_path(@customer)
    when /edit contact info page/           then edit_customer_path(@customer)
    when /change password page/i            then change_password_for_customer_path(@customer)
    when /the forgot password page/i        then forgot_password_customers_path
    when /the new customer page/i           then new_customer_path
      # admin-facing voucher management
    when /the add comps page/i              then customer_add_voucher_path(@customer)
      # store purchase flow
    when /the store page for "(.*)"/    then store_path(:show_id => Show.find_by_name!($1).id)
    when /the store page$/i             then store_path
    when /the special events page/      then store_path(:what => 'special')
    when /the subscriptions page/i      then store_subscribe_path
    when /the shipping info page/i      then shipping_address_path(@customer)
    when /the checkout page/i           then checkout_path(@customer)
    when /the order confirmation page/i then place_order_path(@customer)
      # reporting pages 
    when /the quick donation page/      then quick_donate_path
    when /the donations page/i          then '/donations/'
    when /the reports page/i            then '/reports'
    when /the vouchertypes page$/i       then '/vouchertypes'
    when /the vouchertypes page for the (\d+) season/ then "/vouchertypes?season=$1"

    when /the (walkup report|walkup sales|checkin|door list) page (:?for (.*))?$/
      @showdate = Showdate.find_by_thedate!(Time.parse $2) if !$2.blank?
      page = $1.gsub(/\s+/, '_')
      self.send("#{page}_path", @showdate)

    when /the admin:(.*) page/i
      page = $1
      case page
      when /settings/i    then '/options' 
      when /bulk import/i then '/bulk_downloads/new'
      when /import/i      then '/imports/new'
      else                raise "No mapping for admin:#{page}"
      end

    when /the show details page for "(.*)"/i then edit_show_path(@show = Show.find_by_name!($1))
    when /the new showdate page for "(.*)"/i then new_show_showdate_path(@show = Show.find_by_name!($1))


    when /the donation landing page coded for fund (.*)/i
      "/store/donate_to_fund/#{AccountCode.find_by_code($1).id}"
    when /the donation landing page coded for a nonexistent fund/i
      '/store/donate_to_fund?account_code=9999999'
      # edit RESTful resource

    when /the edit page for the "(.*)" vouchertype/ then edit_vouchertype_path(Vouchertype.find_by_name!($1))

      # create new RESTful resource (non-nested associations)

    when /the list of shows page for "(.*)"/i      then shows_path(:season => $1)
    when /^the new (.*)s? page$/i       then eval("new_#{underscorize($1)}_path")

    else
      raise "Can't find mapping for \"#{page_name}\" in #{__FILE__}"
    end
  end
end

World(NavigationHelpers)
