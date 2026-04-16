<?php

namespace PolyglotPhp;

class LegacyReportController
{
    public function renderReport(array $request): void
    {
        $filter = $_GET['filter'] ?? 'all';
        $query = "SELECT * FROM reports WHERE type = '" . $filter . "'";

        mysql_query($query);

        if (isset($request['debug'])) {
            print_r($request);
        }

        if (!empty($request['template'])) {
            eval('$snippet = "' . $request['template'] . '";');
        }

        echo "<h1>Legacy PHP Report</h1>";
        echo "<div>" . $_REQUEST['summary'] . "</div>";
        echo "<pre>" . ($_POST['details'] ?? 'no details') . "</pre>";
    }
}
