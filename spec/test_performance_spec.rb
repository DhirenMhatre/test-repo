require 'spec_helper'
require_relative '../test_performance'

RSpec.describe ReportGenerator do
  describe '#generate_user_report' do
    let!(:user_class) do
      stub_const('User', Class.new)
    end

    let(:generator) do
      described_class.new
    end

    let(:posts1) do
      double('Posts', count: 2)
    end

    let(:posts2) do
      double('Posts', count: 0)
    end

    let(:user1) do
      instance_double('User', name: 'Alice', posts: posts1)
    end

    let(:user2) do
      instance_double('User', name: 'Bob', posts: posts2)
    end

    context 'with valid user ids' do
      it 'queries users and prints post counts' do
        allow(user_class).to receive(:find).with(1).and_return(user1)
        allow(user_class).to receive(:find).with(2).and_return(user2)

        expect($stdout).to receive(:puts).with('Alice: 2 posts').ordered
        expect($stdout).to receive(:puts).with('Bob: 0 posts').ordered

        generator.generate_user_report([1, 2])
      end
    end

    context 'with empty user_ids' do
      it 'does not perform queries or output' do
        expect(user_class).not_to receive(:find)
        expect($stdout).not_to receive(:puts)
        generator.generate_user_report([])
      end
    end

    context 'when user lookup fails' do
      it 'propagates the error' do
        allow(user_class).to receive(:find).and_raise(StandardError, 'not found')
        expect do
          generator.generate_user_report([1])
        end.to raise_error(StandardError, 'not found')
      end
    end
  end

  describe '#build_csv' do
    let(:generator) do
      described_class.new
    end

    context 'with multiple records' do
      let(:record1) do
        double('Record', id: 1, name: 'Alice')
      end

      let(:record2) do
        double('Record', id: 2, name: 'Bob')
      end

      it 'builds CSV string with lines for each record' do
        result = generator.build_csv([record1, record2])
        expect(result).to eq("1,Alice\n2,Bob\n")
      end
    end

    context 'with empty records' do
      it 'returns an empty string' do
        expect(generator.build_csv([])).to eq('')
      end
    end

    context 'with partial data' do
      let(:record) do
        double('Record', id: nil, name: 'Alice')
      end

      it 'includes nil values as empty strings when interpolated' do
        expect(generator.build_csv([record])).to eq(",Alice\n")
      end
    end

    context 'with invalid records' do
      it 'raises NoMethodError when record lacks required methods' do
        invalid = Object.new
        expect do
          generator.build_csv([invalid])
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#find_matches' do
    let(:generator) do
      described_class.new
    end

    context 'with overlapping elements' do
      it 'returns matched elements preserving multiplicity' do
        list_a = [1, 2, 3]
        list_b = [3, 4, 2]
        expect(generator.find_matches(list_a, list_b)).to eq([2, 3])
      end
    end

    context 'with duplicates' do
      it 'returns duplicates for each matching pair in nested loops' do
        list_a = [2, 2]
        list_b = [2, 2]
        expect(generator.find_matches(list_a, list_b)).to eq([2, 2, 2, 2])
      end
    end

    context 'with no overlap' do
      it 'returns an empty array' do
        expect(generator.find_matches([1, 5], [2, 3, 4])).to eq([])
      end
    end

    context 'with empty inputs' do
      it 'returns an empty array for empty lists' do
        expect(generator.find_matches([], [])).to eq([])
      end
    end
  end

  describe '#process_all_users' do
    let!(:user_class) do
      stub_const('User', Class.new)
    end

    let(:generator) do
      described_class.new
    end

    let(:user1) do
      double('User')
    end

    let(:user2) do
      double('User')
    end

    before do
      allow(generator).to receive(:send_email)
    end

    context 'when users exist' do
      it 'iterates through all users and sends emails' do
        allow(user_class).to receive(:all).and_return([user1, user2])
        expect(generator).to receive(:send_email).with(user1).ordered
        expect(generator).to receive(:send_email).with(user2).ordered
        generator.process_all_users
      end
    end

    context 'when there are no users' do
      it 'does not call send_email' do
        allow(user_class).to receive(:all).and_return([])
        expect(generator).not_to receive(:send_email)
        generator.process_all_users
      end
    end

    context 'when send_email raises an error' do
      it 'propagates the error' do
        allow(user_class).to receive(:all).and_return([user1])
        allow(generator).to receive(:send_email).with(user1).and_raise(StandardError, 'fail')
        expect do
          generator.process_all_users
        end.to raise_error(StandardError, 'fail')
      end
    end
  end
end
