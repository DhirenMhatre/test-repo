require 'spec_helper'
require_relative '../test_performance'

RSpec.describe ReportGenerator do
  let(:report_generator) do
    described_class.new
  end

  describe '#generate_user_report' do
    context 'with valid user ids' do
      let(:user_class) do
        Class.new
      end

      let(:posts1) do
        double(:posts1)
      end

      let(:posts2) do
        double(:posts2)
      end

      let(:user1) do
        double(:user1, name: 'Alice', posts: posts1)
      end

      let(:user2) do
        double(:user2, name: 'Bob', posts: posts2)
      end

      before do
        stub_const('User', user_class)
        expect(user_class).to receive(:find).with(1).and_return(user1).ordered
        expect(user_class).to receive(:find).with(2).and_return(user2).ordered
        expect(posts1).to receive(:count).and_return(2)
        expect(posts2).to receive(:count).and_return(5)
      end

      it 'queries each user and prints the report lines, returning nil' do
        expected_output = "Alice: 2 posts\nBob: 5 posts\n"
        result = nil
        expect do
          result = report_generator.generate_user_report([1, 2])
        end.to output(expected_output).to_stdout
        expect(result).to be_nil
      end
    end

    context 'when no user ids are given' do
      it 'does nothing and returns nil' do
        user_class = Class.new
        stub_const('User', user_class)
        expect(user_class).not_to receive(:find)
        expect do
          expect(report_generator.generate_user_report([])).to be_nil
        end.to output('').to_stdout
      end
    end

    context 'when User.find raises an error' do
      it 'propagates the error' do
        user_class = Class.new
        stub_const('User', user_class)
        allow(user_class).to receive(:find).and_raise(StandardError, 'boom')
        expect do
          report_generator.generate_user_report([123])
        end.to raise_error(StandardError, 'boom')
      end
    end
  end

  describe '#build_csv' do
    let(:record_struct) do
      Struct.new(:id, :name)
    end

    it 'builds a CSV string by concatenation for given records' do
      records = [
        record_struct.new(1, 'Alice'),
        record_struct.new(2, 'Bob')
      ]
      result = report_generator.build_csv(records)
      expect(result).to eq("1,Alice\n2,Bob\n")
    end

    it 'returns an empty string for an empty collection' do
      result = report_generator.build_csv([])
      expect(result).to eq('')
    end

    it 'raises an error when records is nil' do
      expect do
        report_generator.build_csv(nil)
      end.to raise_error(NoMethodError)
    end
  end

  describe '#find_matches' do
    it 'returns matching elements including duplicates based on nested loop logic' do
      list_a = [1, 2, 2, 3]
      list_b = [2, 2, 4]
      result = report_generator.find_matches(list_a, list_b)
      expect(result).to eq([2, 2, 2, 2])
    end

    it 'returns an empty array when either list is empty' do
      expect(report_generator.find_matches([], [1, 2, 3])).to eq([])
      expect(report_generator.find_matches([1, 2, 3], [])).to eq([])
      expect(report_generator.find_matches([], [])).to eq([])
    end

    it 'raises an error when inputs are nil' do
      expect do
        report_generator.find_matches(nil, [1, 2])
      end.to raise_error(NoMethodError)
      expect do
        report_generator.find_matches([1, 2], nil)
      end.to raise_error(NoMethodError)
    end
  end

  describe '#process_all_users' do
    let(:user1) do
      double(:user1)
    end

    let(:user2) do
      double(:user2)
    end

    let(:user_class) do
      Class.new
    end

    before do
      stub_const('User', user_class)
    end

    it 'loads all users and sends an email to each' do
      allow(user_class).to receive(:all).and_return([user1, user2])
      expect(report_generator).to receive(:send_email).with(user1).ordered
      expect(report_generator).to receive(:send_email).with(user2).ordered
      report_generator.process_all_users
    end

    it 'does nothing when there are no users' do
      allow(user_class).to receive(:all).and_return([])
      expect(report_generator).not_to receive(:send_email)
      report_generator.process_all_users
    end

    it 'propagates errors raised by send_email' do
      allow(user_class).to receive(:all).and_return([user1])
      expect(report_generator).to receive(:send_email).with(user1).and_raise(StandardError, 'email failed')
      expect do
        report_generator.process_all_users
      end.to raise_error(StandardError, 'email failed')
    end
  end
end
