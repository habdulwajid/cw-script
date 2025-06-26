
# ----- create:  /etc/nginx/wp_admin_secure.conf ------
location = /wp-login.php {
         if ($allowed = 0){
        return 403;
  }
        try_files $uri = @backend;

}
# Allow specific wp-admin scripts required for frontend or AJAX
location ~* ^/wp-admin/(admin-ajax\.php|admin-post\.php|load-scripts\.php|load-styles\.php|async-upload\.php)$ {
    allow all;
        try_files $uri = @backend;
}
# Allow access to wp-admin JS directory
location ^~ /wp-admin/js/ {
    allow all;
        try_files $uri = @backend;
}
# Block all other /wp-admin/ access
location ~* ^/wp-admin/ {
        if ($allowed = 0){
        return 403;
  }
            try_files $uri = @backend;
}


# /etc/nginx/conf.d/ip_blocakge.conf -- to whitlist the wp-admin access ----
geo $realip_remote_addr $allowed {
    default 0;
proxy 127.0.0.1;
#add IPs here
    66.135.104.155 1;   # BulkWhitelist
}
