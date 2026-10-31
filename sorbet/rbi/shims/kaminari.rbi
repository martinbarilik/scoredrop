# frozen_string_literal: true
# typed: true

# Kaminari defines `page` on models via eval'd code inside an `included do`
# hook, and relations reach it through ActiveRecord::Delegation#method_missing.
# Neither is visible to tapioca, so declare the runtime contract here.
class ActiveRecord::Relation
  sig { params(num: T.untyped).returns(T.self_type) }
  def page(num = nil); end

  sig { params(num: T.untyped).returns(T.self_type) }
  def per(num = nil); end

  sig { params(num: T.untyped).returns(T.self_type) }
  def padding(num = nil); end
end
