#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'ledger'

exit Bench::RunsLedger.run_cli(ARGV)
