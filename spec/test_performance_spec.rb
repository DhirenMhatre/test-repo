require 'spec_helper'
require_relative '../test_performance'

RSpec.describe ReportGenerator do
  subject(:generator) { described_class.new }

  describe '#generate_user_report' do
    let(:user_class) { Class.new }
    let(:posts1) { double('Posts', count: 3) }
    let(:posts2) { double('Posts', count: 0) }
    let(:user1) { instance_double('User', name: 'Alice', posts: posts1) }
    let(:user2) { instance_double('User', name: 'Bob', posts: posts2) }

    before do
      stub_const('User', user_class)
      allow(user_class).to receive(:find)
      allow(user_class).to receive(:find).with(1).and_return(user1)
      allow(user_class).to receive(:find).with(2).and_return(user2)
    end

    it 'queries each user and prints the name with post count' do
      expect do
        generator.generate_user_report([1, 2])
      end.to output("Alice: 3 posts\nBob: 0 posts\n").to_stdout

      expect(user_class).to have_received(:find).with(1)
      expect(user_class).to have_received(:find).with(2)
    end

    context 'with empty user_ids' do
      it 'produces no output and performs no queries' do
        expect do
          generator.generate_user_report([])
        end.to output('').to_stdout

        expect(user_class).not_to have_received(:find)
      end
    end

    context 'when a user lookup fails' do
      before do
        allow(user_class).to receive(:find).with(99).and_raise(StandardError.new('not found'))
      end

      it 'propagates the error' do
        expect do
          generator.generate_user_report([99])
        end.to raise_error(StandardError, 'not found')
      end
    end
  end

  describe '#build_csv' do
    let(:record_class) { Struct.new(:id, :name) }

    it 'builds a CSV string from the given records' do
      records = [record_class.new(1, 'A'), record_class.new(2, 'B')]
      result = generator.build_csv(records)
      expect(result).to eq("1,A\n2,B\n")
    end

    it 'returns an empty string when there are no records' do
      result = generator.build_csv([])
      expect(result).to eq('')
    end

    it 'handles nil attributes by converting them to empty strings' do
      records = [record_class.new(1, nil)]
      result = generator.build_csv(records)
      expect(result).to eq("1,\n")
    end

    it 'raises an error when records is nil' do
      expect do
        generator.build_csv(nil)
      end.to raise_error(NoMethodError)
    end
  end

  describe '#find_matches' do
    it 'returns matches present in both lists including duplicates' do
      result = generator.find_matches([1, 2, 2, 3], [2, 2, 4])
      expect(result).to eq([2, 2, 2, 2])
    end

    it 'returns an empty array when there are no matches' do
      result = generator.find_matches([1, 3], [2, 4])
      expect(result).to eq([])
    end

    it 'returns an empty array when either list is empty' do
      expect(generator.find_matches([], [1, 2])).to eq([])
      expect(generator.find_matches([1, 2], [])).to eq([])
    end

    it 'raises an error when a list is nil' do
      expect do
        generator.find_matches(nil, [])
      end.to raise_error(NoMethodError)
      expect do
        generator.find_matches([], nil)
      end.to raise_error(NoMethodError)
    end
  end

  describe '#process_all_users' do
    let(:user_class) { Class.new }
    let(:user1) { double('User1') }
    let(:user2) { double('User2') }

    before do
      stub_const('User', user_class)
    end

    it 'iterates over all users and sends an email to each' do
      allow(user_class).to receive(:all).and_return([user1, user2])
      allow(generator).to receive(:send_email)

      generator.process_all_users

      expect(generator).to have_received(:send_email).with(user1)
      expect(generator).to have_received(:send_email).with(user2)
    end

    it 'does nothing when there are no users' do
      allow(user_class).to receive(:all).and_return([])
      allow(generator).to receive(:send_email)

      generator.process_all_users

      expect(generator).not_to have_received(:send_email)
    end

    it 'propagates errors from send_email' do
      allow(user_class).to receive(:all).and_return([user1])
      allow(generator).to receive(:send_email).with(user1).and_raise(StandardError.new('boom'))

      expect do
        generator.process_all_users
      end.to raise_error(StandardError, 'boom')
    end
  end
end
