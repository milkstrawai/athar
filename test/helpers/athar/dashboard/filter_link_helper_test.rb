# frozen_string_literal: true

require "test_helper"

module Athar
  module Dashboard
    class FilterLinkHelperTest < ActionView::TestCase
      include Athar::DashboardHelper

      def stub_query_params(params)
        request_double = Struct.new(:query_parameters).new(params.transform_keys(&:to_s))
        stubs(:request).returns(request_double)
        stubs(:root_path).returns("/athar")
      end

      test "no replacements, no current params returns root_path" do
        stub_query_params({})

        assert_equal "/athar", filter_link_url
      end

      test "passes through non-default replacement" do
        stub_query_params({})

        assert_equal "/athar?model=User", filter_link_url(model: "User")
      end

      test "strips replacement equal to its FILTER_DEFAULTS value" do
        stub_query_params({})

        assert_equal "/athar", filter_link_url(time: "30d") # 30d is default
        assert_equal "/athar", filter_link_url(mode: "all") # all is default
        assert_equal "/athar", filter_link_url(kind: "all")
        assert_equal "/athar", filter_link_url(actor: "all")
      end

      test "keeps non-default value for time (default is 30d, not all)" do
        stub_query_params({})

        assert_equal "/athar?time=all", filter_link_url(time: "all")
        assert_equal "/athar?time=24h", filter_link_url(time: "24h")
      end

      test "preserves existing params not being replaced" do
        stub_query_params(model: "User", q: "morgan")
        url = filter_link_url(time: "7d")

        assert_includes url, "model=User"
        assert_includes url, "q=morgan"
        assert_includes url, "time=7d"
      end

      test "strips page and expanded params on every call" do
        stub_query_params(page: "3", expanded: "12345", model: "User")
        url = filter_link_url(time: "7d")

        refute_match(/page=/, url)
        refute_match(/expanded=/, url)
        assert_includes url, "model=User"
        assert_includes url, "time=7d"
      end

      test "replacement overrides existing param of same name" do
        stub_query_params(time: "24h")

        assert_equal "/athar?time=7d", filter_link_url(time: "7d")
      end

      test "blank replacement strips param" do
        stub_query_params(model: "User")
        url = filter_link_url(model: "")

        refute_match(/model=/, url)
      end
    end
  end
end
