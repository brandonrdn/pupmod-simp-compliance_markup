class Hiera
  module Backend
    class Compliance_map_backend
      require 'deep_merge'

      def initialize
        Hiera.debug('Hiera Compliance Map backend starting')

        self.class.instance_variable_set('@compliance_map_recursion_lock', false)
      end

      def lookup(key, scope, order_override, resolution_type, context)
        Hiera.debug("Looking up #{key} in Compliance Map backend")

        answer = nil

        if self.class.instance_variable_get('@compliance_map_recursion_lock')
          Hiera.debug("Compliance Map avoiding recursion loop while looking for #{key}")

          throw :no_such_key
        end

        if Object.const_defined?('Puppet') && Puppet.respond_to?(:lookup) && scope.respond_to?(:real)

          # Ensure that we don't end up in an endless lookup loop
          #
          # This is a *class* instance variable so it will get cleaned up on
          # class destruction, not class instance destruction.
          self.class.instance_variable_set('@compliance_map_recursion_lock', true)

          global_profile_list = Array(retrieve_global(scope.real, 'enforce_compliance_profile'))

          module_profile_list = Array(retrieve_global(scope.real, 'compliance_map::enforce_profiles'))

          compliance_profile_to_enforce = global_profile_list + module_profile_list

          # We're being called from Puppet, so we should try to look things up
          # appropriately
          if !compliance_profile_to_enforce || compliance_profile_to_enforce.empty?
            begin
              # Puppet 4
              global_profile_list = Array(scope.real.call_function('lookup',
                [
                  'enforce_compliance_profile',
                  {
                    'default_value' => []
                  }
                ]
              ))

              module_profile_list = Array(scope.real.call_function('lookup',
                [
                  'compliance_markup::enforce_profiles',
                  {
                    'default_value' => []
                  }
                ]
              ))

              compliance_profile_to_enforce = global_profile_list + module_profile_list

            rescue NoMethodError, Puppet::ParseError
              compliance_profile_to_enforce = nil
            end
          end

          answer = {}
            global_map = scope.real.call_function('lookup',
              [
                'compliance_map',
                {
                  'merge' => 'deep',
                  'default_value' => {}
                }
              ]
            )

          module_map = scope.real.call_function('lookup',
            [
              'compliance_markup::compliance_map',
              {
                'merge' => 'deep',
                'default_value' => {}
              }
            ]
          )

          compliance_map = Backend.merge_answer(
            global_map, module_map,
            { :behavior => 'deeper', :knockout_prefix => '--' }
          )

          # Ensure that we get the most relevant value
          Array(compliance_profile_to_enforce).each do |valid_profile|
            if compliance_map.is_a?(Hash) && compliance_map[valid_profile]

              # Handle knockouts
              if (compliance_map[valid_profile]["--#{key}"])
                answer = nil

                break
              end

              if (compliance_map[valid_profile][key].is_a?(Hash) && compliance_map[valid_profile][key])

                answer = compliance_map[valid_profile][key]

                break
              end
            end
          end

          # Reset for future calls
          self.class.instance_variable_set('@compliance_map_recursion_lock', false)
        end

        throw :no_such_key unless answer

        if answer['value'] && (answer['value'] != '')
          answer = Backend.parse_answer(answer['value'], scope.real, {}, context)
        else
          throw :no_such_key
        end

        if resolution_type == :array
          throw :no_such_key unless answer.is_a?(Array)
        elsif resolution_type.is_a?(Hash) || (resolution_type == :hash)
          throw :no_such_key unless answer.is_a?(Hash)
        elsif answer == ''
          throw :no_such_key
        end

        return answer
      end

      private

      # Hack to work around global warning qualified variable warnings
      def retrieve_global(scope, param)
        if scope.respond_to?(:real)
          scope.real.find_global_scope.to_hash[param]
        else
          scope.find_global_scope.to_hash[param]
        end
      end
    end
  end
end
