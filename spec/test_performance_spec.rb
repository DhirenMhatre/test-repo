require 'spec_helper'
require_relative '../test_performance'

RSpec.describe ReportGenerator do
  let(:generator) do
    described_class.new
  end

  let(:user_class) do
    Class.new
  end

  before do
    stub_const('User', user_class)
  end

  describe '#generate_user_report' do
    context 'with valid user ids' do
      let(:user_ids) do
        [1, 2, 3]
      end

      let(:posts1) do
        double('posts1', count: 2)
      end

      let(:posts2) do
        double('posts2', count: 5)
      end

      let(:posts3) do
        double('posts3', count: 0)
      end

      let(:user1) do
        double('user1', name: 'Alice', posts: posts1)
      end

      let(:user2) do
        double('user2', name: 'Bob', posts: posts2)
      end

      let(:user3) do
        double('user3', name: 'Carol', posts: posts3)
      end

      before do
        allow(User).to receive(:find).and_return(user1, user2, user3)
      end

      it 'queries each user and prints their post counts' do
        expect do
          generator.generate_user_report(user_ids)
        end.to output("Alice: 2 posts\nBob: 5 posts\nCarol: 0 posts\n").to_stdout
      end

      it 'returns the original list of user ids' do
        result = generator.generate_user_report(user_ids)
        expect(result).to eq(user_ids)
      end
    end

    context 'with an empty array' do
      it 'prints nothing and returns empty array' do
        expect do
          result = generator.generate_user_report([])
          expect(result).to eq([])
        end.to output('').to_stdout
      end
    end

    context 'when a lookup fails' do
      it 'raises the error from User.find' do
        allow(User).to receive(:find).and_raise(StandardError, 'boom')
        expect do
          generator.generate_user_report([123])
        end.to raise_error(StandardError, 'boom')
      end
    end

    context 'when input is nil' do
      it 'raises NoMethodError due to calling each on nil' do
        expect do
          generator.generate_user_report(nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#build_csv' do
    context 'with multiple records' do
      let(:record1) do
        double('record', id: 1, name: 'Foo')
      end

      let(:record2) do
        double('record', id: 2, name: 'Bar')
      end

      it 'builds a CSV string with each record on its own line' do
        result = generator.build_csv([record1, record2])
        expect(result).to eq("1,Foo\n2,Bar\n")
      end
    end

    context 'with empty records' do
      it 'returns an empty string' do
        expect(generator.build_csv([])).to eq('')
      end
    end

    context 'with special characters in names' do
      let(:record1) do
        double('record', id: 3, name: 'Line, With, Commas')
      end

      let(:record2) do
        double('record', id: 4, name: "Line\nBreak")
      end

      it 'includes special characters as-is without quoting' do
        result = generator.build_csv([record1, record2])
        expect(result).to eq("3,Line, With, Commas\n4,Line\nBreak\n")
      end
    end

    context 'when a record has nil name' do
      let(:record) do
        double('record', id: 5, name: nil)
      end

      it 'treats nil as empty in interpolation' do
        result = generator.build_csv([record])
        expect(result).to eq("5,\n")
      end
    end

    context 'when records is nil' do
      it 'raises NoMethodError due to calling each on nil' do
        expect do
          generator.build_csv(nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#find_matches' do
    context 'with overlapping arrays' do
      it 'returns items present in both arrays preserving nested loop order' do
        list_a = [1, 2, 3]
        list_b = [3, 4, 1]
        result = generator.find_matches(list_a, list_b)
        expect(result).to eq([1, 3])
      end
    end

    context 'with duplicates in inputs' do
      it 'includes duplicates for each matching pair' do
        list_a = [1, 1]
        list_b = [1, 1, 2]
        result = generator.find_matches(list_a, list_b)
        expect(result).to eq([1, 1, 1, 1])
      end
    end

    context 'with no overlap' do
      it 'returns an empty array' do
        result = generator.find_matches([:a, :b], [:c, :d])
        expect(result).to eq([])
      end
    end

    context 'with empty arrays' do
      it 'returns an empty array' do
        result = generator.find_matches([], [])
        expect(result).to eq([])
      end
    end

    context 'when inputs are nil' do
      it 'raises NoMethodError for nil list_a' do
        expect do
          generator.find_matches(nil, [])
        end.to raise_error(NoMethodError)
      end

      it 'raises NoMethodError for nil list_b' do
        expect do
          generator.find_matches([], nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#process_all_users' do
    context 'with multiple users' do
      let(:user1) do
        double('user1')
      end

      let(:user2) do
        double('user2')
      end

      before do
        allow(User).to receive(:all).and_return([user1, user2])
        allow(generator).to receive(:send_email)
      end

      it 'calls send_email for each user' do
        generator.process_all_users
        expect(generator).to have_received(:send_email).with(user1).once
        expect(generator).to have_received(:send_email).with(user2).once
      end

      it 'returns the enumerated collection' do
        result = generator.process_all_users
        expect(result).to eq([user1, user2])
      end
    end

    context 'with no users' do
      before do
        allow(User).to receive(:all).and_return([])
        allow(generator).to receive(:send_email)
      end

      it 'does not call send_email and returns empty array' do
        result = generator.process_all_users
        expect(generator).not_to have_received(:send_email)
        expect(result).to eq([])
      end
    end

    context 'when send_email raises an error' do
      let(:user) do
        double('user')
      end

      before do
        allow(User).to receive(:all).and_return([user])
        allow(generator).to receive(:send_email).and_raise(StandardError, 'email-fail')
      end

      it 'propagates the error' do
        expect do
          generator.process_all_users
        end.to raise_error(StandardError, 'email-fail')
      end
    end

    context 'when User.all raises an error' do
      before do
        allow(User).to receive(:all).and_raise(StandardError, 'db-down')
      end

      it 'propagates the error' do
        expect do
          generator.process_all_users
        end.to raise_error(StandardError, 'db-down')
      end
    end
  end
end
