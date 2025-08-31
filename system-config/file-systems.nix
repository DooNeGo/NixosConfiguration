{
  fileSystems."/".options = [ "defaults" "noatime" ];
  fileSystems."/home".options = [ "defaults" "noatime" "data=writeback" "journal_async_commit" "commit=10" ];
}
