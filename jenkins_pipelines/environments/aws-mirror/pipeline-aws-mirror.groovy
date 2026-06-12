def run(params) {
    timestamps {
        def tf_source_dir = "${WORKSPACE}/susemanager-ci/terracumber_config/tf_files"
        // Target an isolated build directory so OpenTofu only sees our mirror files
        def tf_isolated_dir = "${WORKSPACE}/results/isolated_mirror_build"
        def awscli = '/usr/local/bin/aws'
        def node_user = 'jenkins'

        try {
            stage('Clone susemanager-ci') {
                dir("susemanager-ci") {
                    checkout scm
                }
                sh """
                    mkdir -p ${tf_isolated_dir}
                    cp ${tf_source_dir}/${params.tf_file} ${tf_isolated_dir}/main.tf
                """
            }

            if (params.must_deploy) {
                stage("Deploy AWS mirror") {
                    echo "Initializing OpenTofu in isolated workspace..."
                    sh "cd ${tf_isolated_dir} && ${params.bin_path} init"

                    echo "Applying OpenTofu Configuration..."
                    sh """
                        cd ${tf_isolated_dir} && ${params.bin_path} apply -auto-approve \
                            -var="AWS_REGION=${params.aws_region}" \
                            -var="AWS_AVAILABILITY_ZONE=${params.aws_availability_zone}" \
                            -var="NAME_PREFIX=${params.name_prefix}-" \
                            -var="MIRROR_VPC_CIDR=${params.mirror_vpc_cidr}" \
                            -var="MIRROR_PRIVATE_IP=${params.mirror_private_ip}" \
                            -var="PEER_VPC_CIDR=${params.peer_vpc_cidr}"
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
