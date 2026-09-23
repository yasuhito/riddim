# frozen_string_literal: true

# Replaces one Herdr module method during a test, then restores its original
# implementation without Ruby's redefine warning or changing later tests.
module HerdrMethodStub
  def with_herdr_method(name, replacement)
    singleton = Riddim::Herdr.singleton_class
    original = singleton.instance_method(name)
    singleton.send(:remove_method, name)
    singleton.send(:define_method, name, &replacement)
    yield
  ensure
    singleton&.send(:remove_method, name)
    singleton&.send(:define_method, name, original) if original
  end
end
