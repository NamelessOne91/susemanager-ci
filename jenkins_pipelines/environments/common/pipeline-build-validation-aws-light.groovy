def run(params) {
    timestamps {
        deployed = false
        env.resultdir = "${WORKSPACE}/results"
        env.resultdirbuild = "${resultdir}/${BUILD_NUMBER}"
        // The junit plugin doesn't affect full paths
        GString junit_resultdir = "results/${BUILD_NUMBER}/results_junit"
        GString sumaform_dir = "${resultdir}/sumaform-aws"
        def awscli = '/usr/local/bin/aws'
        def node_user = 'jenkins'
        
        env.exports = "export BUILD_NUMBER=${BUILD_NUMBER}; export BUILD_VALIDATION=true; export CUCUMBER_PUBLISH_QUIET=true;"
        env.common_params = "--outputdir ${resultdir} --tf susemanager-ci/terracumber_config/tf_files/${params.tf_file} --gitfolder ${sumaform_dir} --bastion_ssh_key ${params.key_file} --terraform-bin ${params.bin_path}"
        ssh_option = '-o StrictHostKeyChecking=no -o ConnectTimeout=7200 -o ServerAliveInterval=60'
        
        String server_ami = params.server_ami ?: ""
        String proxy_ami  = params.proxy_ami ?: ""
        // Public IP for AWS ingress
        String[] ALLOWED_IPS = params.allowed_IPS.split("\n")

        GString tfvarsPrepareScript = "${WORKSPACE}/susemanager-ci/jenkins_pipelines/scripts/tf_vars_generator/prepare_tfvars.py"

        if (params.deploy_parallelism) {
            env.common_params = "${common_params} --parallelism ${params.deploy_parallelism}"
        }
        
        try {
            stage('Clone terracumber, susemanager-ci and sumaform') {
                // Create a directory for  to place the directory with the build results (if it does not exist)
                sh "mkdir -p ${resultdir}"
                git url: params.terracumber_gitrepo, branch: params.terracumber_ref
                dir("susemanager-ci") {
                    checkout scm
                }
                // Clone sumaform with AWS backend
                sh "./terracumber-cli ${common_params} --gitrepo ${params.sumaform_gitrepo} --gitref ${params.sumaform_ref} --runstep gitsync --sumaform-backend aws"
            }

            if (params.must_deploy) {
                stage("Deploy AWS environment") {
                    NAME_PREFIX = env.JOB_NAME.toLowerCase().replace('.', '-')
                    env.aws_configuration = "REGION = \"${params.aws_region}\"\n" +
                            "AVAILABILITY_ZONE = \"${params.aws_availability_zone}\"\n" +
                            "NAME_PREFIX = \"${NAME_PREFIX}-\"\n" +
                            "KEY_FILE = \"${params.key_file}\"\n" +
                            "KEY_NAME = \"${params.key_name}\"\n" +
                            "ALLOWED_IPS = [ \n"
                    ALLOWED_IPS.each { ip ->
                        env.aws_configuration = aws_configuration + "    \"${ip}\",\n"
                    }
                    env.aws_configuration = aws_configuration + "]\n"

                    if (params.mirror != '') {
                        env.aws_configuration = aws_configuration + "MIRROR = \"${params.mirror}\"\n"
                    }

                    writeFile file: "${sumaform_dir}/terraform.tfvars", text: aws_configuration, encoding: "UTF-8"

                    def scriptArgs = " --output ${sumaform_dir}/terraform.tfvars"
                    scriptArgs += " --merge-files ${sumaform_dir}/terraform.tfvars ${params.deployment_tfvars}"
                    scriptArgs += " --inject ARCHITECTURE=${params.architecture}"
                    scriptArgs += " --inject SERVER_AMI=${server_ami}"
                    scriptArgs += " --inject PROXY_AMI=${proxy_ami}"
                    scriptArgs += " --clean --keep-resources ${params.minions_to_run.split(', ').join(' ')}"

                    sh "python3 ${tfvarsPrepareScript} ${scriptArgs}"

                    sh "echo \"export TERRAFORM=${params.bin_path}; export TERRAFORM_PLUGINS=${params.bin_plugins_path}; ./terracumber-cli ${common_params} --logfile ${resultdirbuild}/sumaform-aws.log --init --taint '.*(domain|main_disk).*' --runstep provision --sumaform-backend aws\""
                    sh "export TERRAFORM=${params.bin_path}; export TERRAFORM_PLUGINS=${params.bin_plugins_path}; ./terracumber-cli ${common_params} --logfile ${resultdirbuild}/sumaform-aws.log --init --taint '.*(domain|main_disk).*' --runstep provision --sumaform-backend aws"
                }
            }

            if (params.must_cleanup_env) {
                if (!params.confirm_cleanup) {
                    error("Cleanup not confirmed")
                    sh "exit 1"
                }
                stage('Cleanup AWS environment') {
                    echo "Cleaning up AWS environment ..."
                    sh "echo \"cd ${sumaform_dir} && ${params.bin_path} destroy -auto-approve\""
                    sh "cd ${sumaform_dir} && ${params.bin_path} destroy -auto-approve"
                }
            }
        }
        finally {
            stage('Save TF state') {
                archiveArtifacts artifacts: "results/sumaform/terraform.tfstate, results/sumaform/.terraform/**/*"
            }
        }
    }
}

return this
