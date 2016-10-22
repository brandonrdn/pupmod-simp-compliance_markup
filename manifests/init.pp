class compliance_markup (
  Optional[Array[String[1]]] $validate_profiles = undef,
  Optional[Array[String[1]]] $enforce_profiles  = undef,
  Hash                       $compliance_map    = {},
  Hash                       $options           = {}
) {
  if $compliance_map and !$options['default_map'] {
    $_full_options = $options + { 'default_map' => $compliance_map }
  }
  else {
    $_full_options = $options
  }

  compliance_markup::map { 'execute': options => $_full_options }
}
