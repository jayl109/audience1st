FactoryGirl.define do

  factory :order do
    ignore do
      vouchers_count 0
      contains_donation false
    end
    association :purchaser, :factory => :customer
    association :processed_by, :factory => :customer
    association :customer
    walkup nil
    purchasemethod { Purchasemethod.find_by_shortdesc(:box_cash) }
    sold_on { Time.now }

    after_build do |order|
      if order.walkup
        order.customer = order.purchaser = Customer.walkup_customer
        order.processed_by ||= Customer.boxoffice_daemon
      end
    end
    after_create do |order,evaluator|
      1.upto evaluator.vouchers_count do
        order.items << FactoryGirl.create(:revenue_voucher, :customer => order.customer)
      end
      if evaluator.contains_donation
        order.items << FactoryGirl.create(:donation, :customer => order.customer)
      end
    end
  end
    
end
