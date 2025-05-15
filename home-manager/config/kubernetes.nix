{ pkgs, ... }:
{
  programs.k9s = {
    enable = true;
    settings = { };
    plugin = {
      plugins = {
        # currently requires launching a new terminal instance
        # as k9s doesn't support interactive plugins (from what I can tell)
        # should work with iterm2/other terminals also
        ssm-ssh = {
          shortCut = "s";
          description = "SSH into a node (requires AWS auth and kitty)";
          scopes = [ "node" ];
          background = true;
          command = "sh";
          args = [
            "-c"
            ''
              kubectl get $RESOURCE_NAME $NAME \
                --output=jsonpath="{.metadata.labels.topology\.kubernetes\.io/region}" \
                | xargs printf "AWS_REGION=%s ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=error ubuntu_ssm_sudo@$NAME" \
                | xargs -I{} kitty --title "$NAME" sh -c '{}'
            ''
          ];
        };

        kube-drain = {
          shortCut = "a";
          description = "Drain and shutdown a node using kube-drain";
          scopes = [ "node" ];
          background = true;
          command = "sh";
          args = [
            "-c"
            ''
              kitty --title "kube-drain - $NAME" sh -c 'kube-drain $NAME --as admin --as-group system:masters'
            ''
          ];
        };

        kubelet-config = {
          shortCut = "Ctrl-l";
          description = "View live kubelet config";
          scopes = [ "node" ];
          background = true;
          command = "sh";
          args = [
            "-c"
            ''
              kitty --title "kubelet.yaml - $NAME" sh -c 'kubectl get --as admin --as-group system:masters --raw "/api/v1/nodes/$NAME/proxy/configz" | jq .'
            ''
          ];
        };

        ng-pause = {
          shortCut = "p";
          description = "Pause reconciliation";
          scopes = [ "nodegroups" ];
          background = true;
          command = "ng";
          args = [
            "pause"
            "ng"
            "$NAME"
            "-r"
            "$USER paused using k9s"
            "--as"
            "admin"
            "--as-group"
            "system:masters"
          ];
        };

        ngd-pause = {
          shortCut = "p";
          description = "Pause reconciliation";
          scopes = [ "nodegroupdeployments" ];
          background = true;
          command = "ng";
          args = [
            "pause"
            "ngd"
            "$NAME"
            "-r"
            "$USER paused using k9s"
            "--as"
            "admin"
            "--as-group"
            "system:masters"
          ];
        };

        ng-resume = {
          shortCut = "m";
          description = "Resume reconciliation";
          scopes = [ "nodegroups" ];
          background = true;
          command = "ng";
          args = [
            "resume"
            "ng"
            "$NAME"
            "--as"
            "admin"
            "--as-group"
            "system:masters"
          ];
        };

        ngd-resume = {
          shortCut = "m";
          description = "Resume reconciliation";
          scopes = [ "nodegroupdeployments" ];
          background = true;
          command = "ng";
          args = [
            "resume"
            "ngd"
            "$NAME"
            "--as"
            "admin"
            "--as-group"
            "system:masters"
          ];
        };

        ngd-restart = {
          shortCut = "m";
          description = "Resume reconciliation";
          scopes = [ "nodegroups" ];
          background = true;
          command = "ng";
          args = [
            "resume"
            "ng"
            "$NAME"
            "--as"
            "admin"
            "--as-group"
            "system:masters"
          ];
        };

        ngd-recreate = {
          shortCut = "Ctrl-O";
          description = "Force recreation of active nodegroup";
          scopes = [ "nodegroupdeployments" ];
          background = true;
          command = "ng";
          args = [
            "restart"
            "$NAME"
            "--as"
            "admin"
            "--as-group"
            "system:masters"
          ];
        };

        ng-recreate = {
          shortCut = "Ctrl-O";
          description = "Recreate nodegroup";
          scopes = [
            "ng"
            "nodegroup"
          ];
          background = true;
          command = "bash";
          args = [
            "-c"
            ''
              kubectl annotate --as=admin --as-group=system:masters $RESOURCE_NAME $NAME \
                -n $NAMESPACE \
                "nodegroup-operator.compute.zende.sk/restarted-at=$(date +"%Y-%m-%dT%H:%M:%S%z")"
            ''
          ];
        };
      };
    };
  };
}
