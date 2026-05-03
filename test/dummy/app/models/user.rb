# frozen_string_literal: true

class User < ApplicationRecord
  has_many :sessions, class_name: "SessionRecord", dependent: :destroy
end
