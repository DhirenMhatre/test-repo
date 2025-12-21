require 'spec_helper'
require_relative '../test'

RSpec.describe User do
  describe '#initialize' do
    context 'with a valid name' do
      let(:name) do
        'Alice'
      end

      let(:instance) do
        described_class.new(name)
      end

      it 'sets @name to the provided value' do
        expect(instance.instance_variable_get(:@name)).to eq('Alice')
      end
    end

    context 'with nil name' do
      let(:name) do
        nil
      end

      let(:instance) do
        described_class.new(name)
      end

      it 'sets @name to nil' do
        expect(instance.instance_variable_get(:@name)).to be_nil
      end
    end
  end

  describe '#find_user' do
    let(:name) do
      'Alice'
    end

    let(:instance) do
      described_class.new(name)
    end

    let(:db_double) do
      double('DB')
    end

    before do
      stub_const('DB', db_double)
    end

    context 'when DB returns a user' do
      let(:id) do
        42
      end

      let(:expected_query) do
        "SELECT * FROM users WHERE id = #{id}"
      end

      let(:db_result) do
        [{ 'id' => 42, 'name' => 'Zed' }]
      end

      it 'delegates to DB.execute with the correct SQL and returns its result' do
        expect(db_double).to receive(:execute).with(expected_query).and_return(db_result)
        result = instance.find_user(id)
        expect(result).to eq(db_result)
      end
    end

    context 'when DB returns empty result' do
      let(:id) do
        7
      end

      let(:expected_query) do
        "SELECT * FROM users WHERE id = #{id}"
      end

      it 'returns the empty result from DB' do
        expect(db_double).to receive(:execute).with(expected_query).and_return([])
        result = instance.find_user(id)
        expect(result).to eq([])
      end
    end

    context 'when id is a string' do
      let(:id) do
        '5'
      end

      let(:expected_query) do
        "SELECT * FROM users WHERE id = #{id}"
      end

      it 'passes the string id through in the SQL' do
        expect(db_double).to receive(:execute).with(expected_query).and_return([{ 'id' => 5 }])
        result = instance.find_user(id)
        expect(result).to eq([{ 'id' => 5 }])
      end
    end

    context 'when id is nil' do
      let(:id) do
        nil
      end

      let(:expected_query) do
        'SELECT * FROM users WHERE id = '
      end

      it 'calls DB.execute with SQL containing nil interpolation and returns its result' do
        expect(db_double).to receive(:execute).with(expected_query).and_return(nil)
        result = instance.find_user(id)
        expect(result).to be_nil
      end
    end

    context 'when DB.execute raises an error' do
      let(:id) do
        10
      end

      let(:expected_query) do
        "SELECT * FROM users WHERE id = #{id}"
      end

      it 'propagates the error' do
        expect(db_double).to receive(:execute).with(expected_query).and_raise(StandardError, 'db fail')
        expect do
          instance.find_user(id)
        end.to raise_error(StandardError, 'db fail')
      end
    end
  end

  describe '#bad_method' do
    let(:instance) do
      described_class.new('Bob')
    end

    it 'returns the sum of internal variables' do
      expect(instance.bad_method).to eq(6)
    end
  end
end
