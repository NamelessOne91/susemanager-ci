def run(params) {
    timestamps {
        env.resultdir = "${WORKSPACE}/results"
        env.resultdirbuild = "${resultdir}/${BUILD_NUMBER}"
        GString aws_mirror_dir = "${resultdir}/sumaform-aws"

        def awscli = '/usr/local/bin/aws'
        def node_user = 'jenkins'

        env.common_params = "--outputdir ${resultdir} --tf susemanager-ci/terracumber_config/tf_files/${params.tf_file} --gitfolder ${aws_mirror_dir} --bastion_ssh_key ${params.key_file} --terraform-bin ${params.bin_path}"

        try {
            stage('Clone terracumber, susemanager-ci and sumaform') {
                // Create a directory to place the directory with the build results (if it does not exist)
                sh "mkdir -p ${resultdir}"
                git url: params.terracumber_gitrepo, branch: params.terracumber_ref
                dir("susemanager-ci") {
                    checkout scm
                }
                // Clone sumaform for aws
                sh "./terracumber-cli ${common_params} --gitrepo ${params.sumaform_gitrepo} --gitref ${params.sumaform_ref} --runstep gitsync --sumaform-backend aws"
            }


            if (params.must_deploy) {
                stage("Deploy AWS mirror") {
                    echo "Initializing OpenTofu in isolated workspace..."
                    sh "cd ${tf_isolated_dir} && ${params.bin_path} init"

                    echo "Applying OpenTofu Configuration..."
                    sh """
                        cd ${tf_isolated_dir} && ${params.bin_path} apply -auto-approve \
                            -var="DEPLOY_NAT=${params.must_sync_mirror}" \
                            -var="AWS_REGION=${params.aws_region}" \
                            -var="AWS_AVAILABILITY_ZONE=${params.aws_availability_zone}" \
                            -var="NAME_PREFIX=${params.name_prefix}-" \
                            -var="MIRROR_VPC_CIDR=${params.mirror_vpc_cidr}" \
                            -var="MIRROR_PRIVATE_IP=${params.mirror_private_ip}" \
                            -var="PEER_VPC_CIDR=${params.peer_vpc_cidr}" \
                            -var="SSH_KEY=${params.ssh_key}" \
                            -var='ALLOWED_IPS=[${params.allowed_ips.split("\n").collect{ "\"${it.trim()}\"" }.join(",")}]'
                    """
                }
            }

            if (params.must_sync_mirror) {
                stage("Sync AWS mirror") {
                    echo "Syncing AWS mirror with rsync over SSM ..."
                    echo "TODO: implement the sync using AWS SSM to run the rsync command on the mirror host, using the provided AWS CLI and credentials"
                }
            }

            if (params.must_cleanup_env) {
                if (!params.confirm_cleanup) {
                    error("Cleanup not confirmed")
                    sh "exit 1"
                }
                stage('Cleanup AWS mirror environment') {
                    echo "Cleaning up AWS mirror environment ..."
                    sh "cd ${tf_isolated_dir} && ${params.bin_path} destroy -auto-approve"
                }
            }
        }
        finally {
            stage('Archive State') {
                dir(tf_isolated_dir) {
                    archiveArtifacts artifacts: "terraform.tfstate, .terraform.lock.hcl", allowEmptyArchive: true
                }
            }
        }
    }
}

return this
