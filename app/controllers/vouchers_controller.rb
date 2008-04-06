class VouchersController < ApplicationController

  before_filter :is_logged_in
  before_filter(:is_boxoffice_manager_filter,
                :only => %w[addvoucher remove_voucher cancel_prepaid])
  before_filter(:owns_voucher_or_is_boxoffice, 
                :only => %w[reserve confirm_reservation cancel_reservation])
  before_filter(:is_boxoffice_filter, :only => %w[update_comment] )

  verify(:method => :post,
         :only => %w[confirm_reservation cancel_reservation cancel_prepaid
                        remove_voucher],
         :add_to_flash => "System error: This operation must be a POST",
         :redirect_to => {:controller => 'customers', :action => 'welcome'})

  def addvoucher
    unless (@customer = @gCustomer)
      flash[:notice] = "Must select a customer to add vouchers"
      redirect_to :controller => 'customers', :action => 'list'
      return
    end
    # can this be declared as a filter?
    unless Vouchertype.find(:first)
      flash[:notice] = "You must define some vouchertypes first"
      redirect_to :controller => 'vouchertypes', :action => 'list'
      return
    end
    if request.get?
      @regular_vouchers = Vouchertype.find(:all, :conditions => 'is_bundle = 0')
      @bundle_vouchers = Vouchertype.find(:all, :conditions => 'is_bundle = 1')
      @purchasemethods = Purchasemethod.find(:all)
      # fall through to rendering
      return
    end

    thenumtoadd = params[:howmany].to_i
    thevouchertype = params[:vouchertype_id].to_i
    thevouchername = (vt = Vouchertype.find(thevouchertype)).name
    thepurchasemethod = params[:purchasemethod_id].to_i
    thepurchasemethodname = (pm = Purchasemethod.find(thepurchasemethod)).description
    # if comp vouchers are being added, only purchasemethod allowed
    #  is 'no payment necessary'
    if vt.price.zero? && !pm.nonrevenue?
      flash[:notice] = "Only the following payment methods are valid for " <<
        "zero-cost vouchers: " <<
        Purchasemethod.find_all_by_nonrevenue(true).map {|s| s.description}.join(', ')
      redirect_to :action => :addvoucher
      return
    end
      
    fulfillment_needed = params[:fulfillment_needed] 
    thecomment = params[:comment]
    custid = @customer.id
    begin
      v = Voucher.add_vouchers_for_customer(thevouchertype, thenumtoadd,
                                            @customer,thepurchasemethod, 0,
                                            thecomment, logged_in_id,
                                            fulfillment_needed)
      if (v.kind_of?(Array))
        flash[:notice] = thecomment + " for customer #{@customer.full_name}"
        Txn.add_audit_record(:txn_type => 'add_tkts', :customer_id => custid,
                             :voucher_id => v.first.id,
                             :comments => thecomment,
                             :logged_in_id => logged_in_id,
                             :purchasemethod_id => thepurchasemethod)
      else
        flash[:notice] = "Add voucher failed: #{v}"
      end
    rescue Exception => e
      flash[:notice] = "Error adding vouchers:<br/>#{e.message}"
    end
    redirect_to :controller => 'customers', :action => 'welcome'
  end
  
  def remove_voucher
    v = Voucher.find(params[:id])
    if v.nil? 
      flash[:notice] = 'Voucher not found! Please logout and login again to re-sync.'
    else
      old_voucher_id = v.id
      old_cust_id = v.customer.id
      unless v.reserved?
        comment = ''
        v.destroy
        flash[:notice] = 'Voucher removed'
        Txn.add_audit_record(:txn_type => 'del_tkts',
                             :customer_id => @gCustomer.id, 
                             :logged_in_id => logged_in_id, 
                             :voucher_id => old_voucher_id, 
                             :comments => comment)
      else
        flash[:notice] = 'Voucher not removed, must cancel reservation first'
      end
    end
    redirect_to :controller => 'customers', :action => 'welcome', :id => old_cust_id
  end
  
  def update_comment
    who = logged_in_id rescue Customer.nobody_id
    if (voucher = Voucher.find_by_id(params[:vid]))
      voucher.update_attributes({:comments => params[:comments],
                                  :processed_by => who})
      Txn.add_audit_record(:txn_type => 'edit',
                           :customer_id => voucher.customer.id,
                           :voucher_id => voucher.id,
                           :comments => params[:comments],
                           :logged_in_id => logged_in_id)
    end
    render :nothing => true
  end

  def reserve                     
    @voucher = Voucher.find(params[:id]) # this is the voucher that customer wants to use
    @customer = @voucher.customer
    @is_admin = Customer.find(logged_in_id).is_walkup rescue nil
    try_again("Voucher already used: #{@voucher.showdate.printable_name}") and return unless @voucher.not_already_used
    showdates = (@is_admin ?
                 Showdate.find(:all) :
                 Showdate.find(:all,:conditions => ["thedate > ?", Time.now]))
    @available_seats = showdates.map do |s|
      ValidVoucher.numseats_for_showdate_by_vouchertype(s,@customer,@voucher.vouchertype,:redeeming => true,:ignore_cutoff => @is_admin)
    end
  end
  
  def confirm_multiple
    @is_admin = @gAdmin.is_walkup # really need to do this?? not in prefilter??
    @customer = @gCustomer
    try_again("Please select a date.") and return if
      (showdate = params[:showdate_id].to_i).zero?
    num = params[:number].to_i
    count = 0
    lasterr = 'errors occurred making reservations'
    Voucher.find(params[:voucher_ids].split(",")).slice(0,num).each do |v|
      if v.reserve_for(showdate, logged_in_id, "", :ignore_cutoff => @is_admin)
        count += 1
      else
        lasterr = v.comments
      end
    end
    case count
    when 0
      flash[:notice] = "Your reservations could not be completed (#{lasterr})."
    when num
      flash[:notice] = "Your reservations are confirmed."
      email_confirmation(:confirm_reservation, @customer, showdate, count)
    else
      flash[:notice] = "Some of your reservations could not be completed " <<
        "(#{lasterr}).  Please check the results below carefully before " <<
        "continuing."
      email_confirmation(:confirm_reservation, @customer, showdate, count)
    end
    redirect_to :controller => 'customers', :action => 'welcome'
  end

  def confirm_reservation
    @voucher = Voucher.find(params[:id])
    @customer = @voucher.customer
    @is_admin = @gAdmin.is_walkup
    try_again("Please select a date") and return if
      (showdate = params[:showdate_id].to_i).zero?
    if (a = @voucher.reserve_for(showdate, logged_in_id,
                                 params[:comments], :ignore_cutoff => @is_admin))
      flash[:notice] = "Reservation confirmed. " <<
        "Your confirmation number is #{a}."
      email_confirmation(:confirm_reservation, @customer, showdate, 1, a)
    else
      flash[:notice] = "Sorry, can't complete this reservation: #{@voucher.comments}"
    end
    redirect_to :controller => 'customers',:action => 'welcome',:id => @customer
  end

  def cancel_prepaid
    # A prepaid ticket can be cancelled at any time, but the voucher is 
    # NOT reused.  it is "orphaned" and not linked to any customer or
    # show, but the record of its existence remains so that we can track
    # the fact that it was sold.  Its ID number will still be referred
    # to in the audit log.
    @v = Voucher.find(params[:id])
    try_again("Please cancel this reservation before removing the voucher.") and return if @v.changeable
    save_showdate = @v.showdate.id
    save_show = @v.showdate.show.id
    save_customer = @v.customer.id
    @v.showdate = nil
    @v.customer = nil
    @v.processed_by = logged_in_id
    @v.save!
    Txn.add_audit_record(:txn_type => 'res_cancl',
                         :customer_id => @gCustomer.id,
                         :voucher_id => params[:id],
                         :logged_in_id => logged_in_id,
                         :show_id => save_show,
                         :showdate => save_showdate,
                         :comment => 'Prepaid, comp or other nonsubscriber ticket')
    flash[:notice] = "Reservation cancelled, voucher unlinked from customer"
    redirect_to :controller => 'customers', :action => 'welcome'
  end

  def cancel_multiple
    vchs = Voucher.find(params[:voucher_ids].split(","))
    old_showdate = vchs.first.showdate.clone
    vchs.each do |v|
      if v.can_be_changed?(logged_in_id)
        showdate = v.showdate
        showdate_id = showdate.id
        show_id = showdate.show.id
        v.cancel(logged_in_id)
        a = Txn.add_audit_record(:txn_type => 'res_cancl',
                                 :customer_id => @gCustomer.id,
                                 :logged_in_id => logged_in_id,
                                 :showdate_id => showdate_id,
                                 :show_id => show_id,
                                 :voucher_id => v.id)
      else
        flash[:notice] ||= "Some reservations could NOT be cancelled. " <<
          "Please review your reservations below and contact a " <<
          "box office agent if you need assistance."
      end
    end
    flash[:notice] ||= "Your reservations have been cancelled. " <<
      "Your cancellation confirmation number is #{a}. "
    email_confirmation(:cancel_reservation, @gCustomer, old_showdate,
                       vchs.length, a)
    redirect_to :controller => 'customers', :action => 'welcome'
  end
    

  def cancel_reservation
    @v = Voucher.find(params[:id])
    unless @v.can_be_changed?(logged_in_id)
      (flash[:notice] ||= "") << "This reservation is not changeable"
    else
      showdate = @v.showdate
      old_showdate = showdate.clone
      showdate_id = showdate.id
      show_id = showdate.show.id
      if @v.cancel(logged_in_id)
        a= Txn.add_audit_record(:txn_type => 'res_cancl',
                                :customer_id => @gCustomer.id, 
                                :logged_in_id => logged_in_id, 
                                :showdate_id => showdate_id,
                                :show_id => show_id,
                                :voucher_id => @v.id)
        flash[:notice] = "Your reservation has been cancelled. " <<
          "Your cancellation confirmation number is #{a}. "
        email_confirmation(:cancel_reservation, @gCustomer, old_showdate, 1, a)
      else
        flash[:notice] = 'Error - reservation could not be cancelled'
      end
    end
    redirect_to :controller => 'customers', :action => 'welcome'
  end

  def owns_voucher_or_is_boxoffice
    return true if is_walkup    # or higher
    return true if (params[:id] &&
                    (voucher = Voucher.find(params[:id].to_i)) &&
                    (voucher.customer.id == @gCustomer.id)) rescue nil
    flash[:notice] = "Attempt to reserve a voucher that isn't yours."
    redirect_to(:controller => 'customers', :action => 'logout')
    return false
  end

  private

  def try_again(msg)
    flash[:notice] = msg
    redirect_to :controller => 'customers', :action => 'welcome'
  end
  
end
