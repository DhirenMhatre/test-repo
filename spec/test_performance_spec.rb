require 'spec_helper'
require_relative '../test_performance'

RSpec.describe ReportGenerator do
  describe '#generate_user_report' do
    let(:service) { described_class.new }

    context 'with multiple user ids' do
      let(:user_ids) { [1, 2, 3] }

      before do
        stub_const('User', double('User'))
        allow($stdout).to receive(:puts)
        allow(User).to receive(:find) do |id|
          posts = double("Posts_#{id}", count: id * 2)
          instance_double('User', name: "User#{id}", posts: posts)
        end
      end

      it 'finds each user, queries posts count, prints output, and returns the original ids' do
        expect(User).to receive(:find).with(1).and_call_original
        expect(User).to receive(:find).with(2).and_call_original
        expect(User).to receive(:find).with(3).and_call_original

        expect($stdout).to receive(:puts).with('User1: 2 posts')
        expect($stdout).to receive(:puts).with('User2: 4 posts')
        expect($stdout).to receive(:puts).with('User3: 6 posts')

        result = service.generate_user_report(user_ids)
        expect(result).to eq(user_ids)
      end
    end

    context 'with empty list' do
      before do
        stub_const('User', double('User'))
        allow($stdout).to receive(:puts)
      end

      it 'does not perform any lookup and returns an empty array' do
        expect(User).not_to receive(:find)
        result = service.generate_user_report([])
        expect(result).to eq([])
      end
    end

    context 'when a user lookup fails' do
      let(:user_ids) { [42] }

      before do
        stub_const('User', double('User'))
        allow($stdout).to receive(:puts)
        allow(User).to receive(:find).with(42).and_raise(StandardError, 'not found')
      end

      it 'propagates the error' do
        expect do
          service.generate_user_report(user_ids)
        end.to raise_error(StandardError, 'not found')
      end
    end
  end

  describe '#build_csv' do
    let(:service) { described_class.new }
    let(:record_struct) { Struct.new(:id, :name) }

    context 'with multiple records' do
      let(:records) { [record_struct.new(1, 'Alice'), record_struct.new(2, 'Bob')] }

      it 'returns a newline-delimited CSV string without headers' do
        result = service.build_csv(records)
        expect(result).to eq("1,Alice\n2,Bob\n")
      end
    end

    context 'with empty records' do
      it 'returns an empty string' do
        result = service.build_csv([])
        expect(result).to eq('')
      end
    end

    context 'with nil values' do
      let(:records) { [record_struct.new(3, nil)] }

      it 'serializes nil as empty fields' do
        result = service.build_csv(records)
        expect(result).to eq("3,\n")
      end
    end

    context 'with invalid record object' do
      it 'raises an error when record does not respond to id/name' do
        invalid = [Object.new]
        expect do
          service.build_csv(invalid)
        end.to raise_error(NoMethodError)
      end
    end

    context 'when records is nil' do
      it 'raises an error' do
        expect do
          service.build_csv(nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#find_matches' do
    let(:service) { described_class.new }

    context 'with overlapping items and duplicates' do
      let(:list_a) { [1, 2, 2, 3] }
      let(:list_b) { [2, 2, 4] }

      it 'returns matches for each occurrence (cartesian duplicate matches)' do
        result = service.find_matches(list_a, list_b)
        expect(result).to eq([2, 2, 2, 2])
      end
    end

    context 'with no overlaps' do
      let(:list_a) { [1, 5] }
      let(:list_b) { [2, 3, 4] }

      it 'returns an empty array' do
        result = service.find_matches(list_a, list_b)
        expect(result).to eq([])
      end
    end

    context 'with empty lists' do
      it 'returns empty when list_a is empty' do
        result = service.find_matches([], [1, 2, 3])
        expect(result).to eq([])
      end

      it 'returns empty when list_b is empty' do
        result = service.find_matches([1, 2, 3], [])
        expect(result).to eq([])
      end
    end

    context 'with nils present' do
      let(:list_a) { [nil, 1, nil] }
      let(:list_b) { [nil, 2] }

      it 'matches nils as well' do
        result = service.find_matches(list_a, list_b)
        expect(result).to eq([nil, nil])
      end
    end

    context 'invalid inputs' do
      it 'raises when list_a is nil' do
        expect do
          service.find_matches(nil, [1, 2])
        end.to raise_error(NoMethodError)
      end

      it 'raises when list_b is nil' do
        expect do
          service.find_matches([1, 2], nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#process_all_users' do
    let(:service) { described_class.new }

    context 'with users present' do
      let(:user1) { instance_double('User', id: 1) }
      let(:user2) { instance_double('User', id: 2) }

      before do
        stub_const('User', double('User'))
        allow(User).to receive(:all).and_return([user1, user2])
      end

      it 'calls send_email for each user' do
        expect(service).to receive(:send_email).with(user1).ordered
        expect(service).to receive(:send_email).with(user2).ordered
        service.process_all_users
      end
    end

    context 'with no users' do
      before do
        stub_const('User', double('User'))
        allow(User).to receive(:all).and_return([])
      end

      it 'does not call send_email' do
        expect(service).not_to receive(:send_email)
        service.process_all_users
      end
    end

    context 'when send_email raises for a user' do
      let(:user1) { instance_double('User', id: 1) }
      let(:user2) { instance_double('User', id: 2) }

      before do
        stub_const('User', double('User'))
        allow(User).to receive(:all).and_return([user1, user2])
      end

      it 'propagates the error and stops processing subsequent users' do
        error = RuntimeError.new('boom')
        expect(service).to receive(:send_email).with(user1).and_raise(error)
        expect(service).not_to receive(:send_email).with(user2)
        expect do
          service.process_all_users
        end.to raise_error(RuntimeError, 'boom')
      end
    end
  end
end
