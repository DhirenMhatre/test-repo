require 'spec_helper'
require_relative '../test_performance'

RSpec.describe ReportGenerator do
  subject(:generator) do
    described_class.new
  end

  describe '#generate_user_report' do
    let(:user1) do
      double('User1', name: 'Alice', posts: posts1)
    end

    let(:user2) do
      double('User2', name: 'Bob', posts: posts2)
    end

    let(:posts1) do
      double('Posts1', count: 3)
    end

    let(:posts2) do
      double('Posts2', count: 5)
    end

    before do
      stub_const('User', Class.new)
      allow(User).to receive(:find) do |id|
        if id == 1
          user1
        elsif id == 2
          user2
        else
          raise StandardError, 'not found'
        end
      end
    end

    context 'with valid user ids' do
      let(:user_ids) do
        [1, 2]
      end

      it 'queries each user and prints their post counts, returning the original array' do
        original_stdout = $stdout
        io = StringIO.new
        $stdout = io
        begin
          result = generator.generate_user_report(user_ids)
          expect(result).to eq(user_ids)
          expect(io.string).to include('Alice: 3 posts')
          expect(io.string).to include('Bob: 5 posts')
        ensure
          $stdout = original_stdout
        end
      end
    end

    context 'with an empty array' do
      let(:user_ids) do
        []
      end

      it 'does not perform any queries and returns an empty array' do
        expect(User).not_to receive(:find)
        original_stdout = $stdout
        io = StringIO.new
        $stdout = io
        begin
          result = generator.generate_user_report(user_ids)
          expect(result).to eq([])
          expect(io.string).to eq('')
        ensure
          $stdout = original_stdout
        end
      end
    end

    context 'when user lookup fails for one of the ids' do
      let(:user_ids) do
        [1, 999]
      end

      it 'raises an error and does not continue after the failure' do
        original_stdout = $stdout
        io = StringIO.new
        $stdout = io
        begin
          expect do
            generator.generate_user_report(user_ids)
          end.to raise_error(StandardError, /not found/)
          expect(io.string).to include('Alice: 3 posts')
        ensure
          $stdout = original_stdout
        end
      end
    end

    context 'with nil as input' do
      it 'raises NoMethodError' do
        expect do
          generator.generate_user_report(nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#build_csv' do
    let(:record1) do
      double('Record1', id: 1, name: 'Alice')
    end

    let(:record2) do
      double('Record2', id: 2, name: 'Bob')
    end

    context 'with valid records' do
      let(:records) do
        [record1, record2]
      end

      it 'concatenates into a CSV-like string with newline per record' do
        csv = generator.build_csv(records)
        expect(csv).to eq("1,Alice\n2,Bob\n")
      end
    end

    context 'with empty records' do
      let(:records) do
        []
      end

      it 'returns an empty string' do
        csv = generator.build_csv(records)
        expect(csv).to eq('')
      end
    end

    context 'with special characters in fields' do
      let(:record3) do
        double('Record3', id: 3, name: "Carol, Inc.\nLLC")
      end

      it 'includes raw values without escaping' do
        csv = generator.build_csv([record3])
        expect(csv).to eq("3,Carol, Inc.\nLLC\n")
      end
    end

    context 'with nil input' do
      it 'raises NoMethodError' do
        expect do
          generator.build_csv(nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#find_matches' do
    context 'with overlapping elements' do
      let(:list_a) do
        [1, 2, 3]
      end

      let(:list_b) do
        [2, 3, 4]
      end

      it 'returns elements present in both lists' do
        matches = generator.find_matches(list_a, list_b)
        expect(matches).to eq([2, 3])
      end
    end

    context 'with duplicates in list_b' do
      let(:list_a) do
        [1, 2]
      end

      let(:list_b) do
        [2, 2]
      end

      it 'returns duplicates for each matching pair' do
        matches = generator.find_matches(list_a, list_b)
        expect(matches).to eq([2, 2])
      end
    end

    context 'with empty lists' do
      let(:list_a) do
        []
      end

      let(:list_b) do
        []
      end

      it 'returns an empty array' do
        matches = generator.find_matches(list_a, list_b)
        expect(matches).to eq([])
      end
    end

    context 'with mixed types' do
      let(:list_a) do
        ['1', 1]
      end

      let(:list_b) do
        [1]
      end

      it 'matches only by strict equality' do
        matches = generator.find_matches(list_a, list_b)
        expect(matches).to eq([1])
      end
    end

    context 'with nil input' do
      it 'raises NoMethodError when list_a is nil' do
        expect do
          generator.find_matches(nil, [])
        end.to raise_error(NoMethodError)
      end

      it 'raises NoMethodError when list_b is nil' do
        expect do
          generator.find_matches([], nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#process_all_users' do
    let(:user_a) do
      double('UserA')
    end

    let(:user_b) do
      double('UserB')
    end

    before do
      stub_const('User', Class.new)
    end

    context 'with users returned by User.all' do
      let(:users) do
        [user_a, user_b]
      end

      before do
        allow(User).to receive(:all).and_return(users)
      end

      it 'sends email to each user and returns the enumerated collection' do
        expect(generator).to receive(:send_email).with(user_a).once
        expect(generator).to receive(:send_email).with(user_b).once
        result = generator.process_all_users
        expect(result).to eq(users)
      end
    end

    context 'with an empty user list' do
      let(:users) do
        []
      end

      before do
        allow(User).to receive(:all).and_return(users)
      end

      it 'does not call send_email and returns the empty collection' do
        expect(generator).not_to receive(:send_email)
        result = generator.process_all_users
        expect(result).to eq([])
      end
    end

    context 'when send_email raises for a user' do
      let(:users) do
        [user_a, user_b]
      end

      before do
        allow(User).to receive(:all).and_return(users)
      end

      it 'raises the error and stops processing further users' do
        expect(generator).to receive(:send_email).with(user_a).once
        expect(generator).to receive(:send_email).with(user_b).and_raise('boom')
        expect do
          generator.process_all_users
        end.to raise_error(RuntimeError, 'boom')
      end
    end

    context 'when User.all is not enumerable' do
      before do
        allow(User).to receive(:all).and_return(nil)
      end

      it 'raises NoMethodError' do
        expect do
          generator.process_all_users
        end.to raise_error(NoMethodError)
      end
    end
  end
end
