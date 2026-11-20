#include <linux/init.h>
#include <linux/module.h>

static int __init test_init(void)
{
	pr_info("test module init.\n");
	return 0;
}

static void __exit test_exit(void)
{
	pr_info("test module eixt.\n");
}

module_init(test_init);
module_exit(test_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Huang Liang");
MODULE_DESCRIPTION("Minimal kernel module test");