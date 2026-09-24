# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/riddim/merge_local'

class MergeLocalTest < Minitest::Test
  def shape_refusal(value)
    Riddim::MergeLocal.verify_reviewed_shape!(value)
    nil
  rescue Riddim::MergeLocal::Refused => e
    e
  end

  def test_reviewed_head_requires_a_full_commit_id
    refusal = shape_refusal('abc123')

    assert_equal [Riddim::MergeLocal::Refused, 'the reviewed head must be a full commit id'],
                 [refusal&.class, refusal&.message]
  end

  def test_reviewed_head_accepts_either_full_git_hash_length
    assert_nil shape_refusal("#{'a' * 40}#{'b' * 24}")
  end
end
