FactoryGirl.define do

  factory :customer do
    ignore do
      role :patron
    end
    sequence(:first_name) { |n| "Joe#{n}" }
    sequence(:last_name) { |n| "Doe#{n}" }
    sequence(:email) { |n| "joe#{n}@yahoo.com" }
    password 'xxxxx'
    password_confirmation 'xxxxx'
    day_phone '212-555-5555'
    street '123 Fake St'
    city 'New York'
    state 'NY'
    zip '10019'
    created_by_admin false

    after_build do |customer,evaluator|
      customer.role = Customer.role_value(evaluator.role) unless evaluator.role == :patron
    end
  end

end
