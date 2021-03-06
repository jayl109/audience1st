class LapsedSubscribers < Report

  def initialize(output_options = {})
    sub_vouchers =  Vouchertype.subscription_vouchertypes
    @view_params = {
      :name => "Lapsed subscribers report",
      :have_vouchertypes => sub_vouchers,
      :dont_have_vouchertypes => sub_vouchers
    }
    super
  end

  def generate(params={})
    have = Report.list_of_ints_from_multiselect(params[:have_vouchertypes])
    have_not = Report.list_of_ints_from_multiselect(params[:dont_have_vouchertypes])
    if have.empty? && have_not.empty?
      add_error "You must specify at least one type of voucher from at least one list."
      return nil
    end
    purchased_any = if have.empty? then Customer.all_customers else
                      Customer.purchased_any_vouchertypes(have) end
    if have_not.empty?
      purchased_any
    else
      purchased_any & Customer.purchased_no_vouchertypes(have_not)
    end
  end
end
