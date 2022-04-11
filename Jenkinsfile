pipeline {
  agent any

  stages {
    stage('Build') {
        when {
            expression {
                env.JENKINS_URL.contains('gauntlet')
            }
        }
        steps {
            library 'gauntlet'
            checkoutToLocalBranch()
            wrap([$class: 'VaultBuildWrapper', vaultSecrets: [
                    [$class: 'VaultSecret', path: "secret/xeng/gauntlet/artifactory/aws/gauntlet", secretValues: [
                      [$class: 'VaultSecretValue', envVar: 'ARTIFACTORY_USER', vaultKey: 'username'],
                      [$class: 'VaultSecretValue', envVar: 'ARTIFACTORY_API_TOKEN', vaultKey: 'token'],
                    ]],
                    [$class: 'VaultSecret', path: "dx_analytics_edge/analytics-data-collection/service_accounts/gauntlet-build-account", secretValues: [
                      [$class: 'VaultSecretValue', envVar: 'AWS_ACCESS_KEY_ID', vaultKey: 'access-key-id'],
                      [$class: 'VaultSecretValue', envVar: 'AWS_SECRET_ACCESS_KEY', vaultKey: 'secret-access-key'],
                    ]]
            ]]) {
                sh "git submodule init && git submodule sync && git submodule update --init --recursive"
                sh 'mkdir -p build/output && ln -s build/output buildrunner.results'
                sh 'make clean all publish'
                script {
                    com.adobe.buildrunner.BuildrunnerUtils.processArtifacts(this)
                }
            }
        }
    }
  }
}
