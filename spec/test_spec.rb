require 'spec_helper'
require_relative '../test'

RSpec.describe User do
  describe '#initialize' do
    context 'with a valid name' do
      let(:name) do
        'Alice'
      end

      let(:user) do
        described_class.new(name)
      end

      it 'sets the @name instance variable' do
        expect(user.instance_variable_get(:@name)).to eq('Alice')
      end
    end

    context 'with nil name' do
      let(:name) do
        nil
      end

      let(:user) do
        described_class.new(name)
      end

      it 'allows nil name' do
        expect(user.instance_variable_get(:@name)).to be_nil
      end
    end

    context 'when called with no arguments' do
      it 'raises ArgumentError' do
        expect do
          described_class.new
        end.to raise_error(ArgumentError)
      end
    end
  end

  describe '#find_user' do
    let(:user) do
      described_class.new('Bob')
    end

    let(:db_double) do
      double('DB')
    end

    before do
      stub_const('DB', db_double)
    end

    context 'with numeric id' do
      let(:id) do
        42
      end

      let(:db_result) do
        ['row1']
      end

      before do
        allow(DB).to receive(:execute).with('SELECT * FROM users WHERE id = 42').and_return(db_result)
      end

      it 'calls DB.execute with interpolated SQL and returns its result' do
        expect(user.find_user(id)).to eq(db_result)
      end
    end

    context 'with string id containing SQL injection' do
      let(:id) do
        '1; DROP TABLE users;'
      end

      let(:db_result) do
        ['row1']
      end

      before do
        allow(DB).to receive(:execute).with('SELECT * FROM users WHERE id = 1; DROP TABLE users;').and_return(db_result)
      end

      it 'passes the raw interpolated SQL to DB.execute' do
        expect(user.find_user(id)).to eq(db_result)
      end
    end

    context 'when DB.execute raises an error' do
      before do
        allow(DB).to receive(:execute).and_raise(StandardError, 'db error')
      end

      it 'propagates the exception' do
        expect do
          user.find_user(1)
        end.to raise_error(StandardError, 'db error')
      end
    end

    context 'with nil id' do
      let(:id) do
        nil
      end

      let(:db_result) do
        []
      end

      before do
        allow(DB).to receive(:execute).with('SELECT * FROM users WHERE id = ').and_return(db_result)
      end

      it 'calls DB.execute with the resulting query and returns its result' do
        expect(user.find_user(id)).to eq(db_result)
      end
    end
  end

  describe '#bad_method' do
    let(:user) do
      described_class.new('Charlie')
    end

    it 'returns the sum of 1, 2, and 3 as 6' do
      expect(user.bad_method).to eq(6)
    end

    it 'returns an Integer' do
      expect(user.bad_method).to be_a(Integer)
    end
  end
end
