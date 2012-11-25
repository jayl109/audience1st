class OrdersController < ApplicationController
  before_filter :is_boxoffice

  def show
    @order = Order.find_by_id(params[:id])
    if @order.nil?
      flash[:warning] = "No order found"
      redirect_to_stored
    end
    @total = @order.items.inject(0) { |sum,p| sum+p.amount }
    @refund_msg = "Upon refund, the customer's credit card charge will be reversed and all of these items will be permanently destroyed, which cannot be undone.  If the refund fails, all items will stay exactly as they are.  Do you want to proceed with the refund?" # "
    @printable = params[:printable]
    render :layout => false if @printable
  end

end