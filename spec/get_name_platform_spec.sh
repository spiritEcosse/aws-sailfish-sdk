Describe 'funcs.sh'
  Include funcs.sh
  It 'Determine platform of system.'
    When call get_name_platform
    The output should equal 'darwin'
  End

  It 'Determine platform of system.'
      uname() {
        echo "GNU/Linux localhost 4.12.0-rc6-g48ec1f0-dirty #21 Fri Aug 4 21:02:28 CEST 2017 i586
              Linux"
      }

      awk() {
        echo "ubuntu"
      }

      When call get_name_platform
      The output should equal 'ubuntu'
  End
End
